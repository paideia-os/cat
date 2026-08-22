# cat — architecture

**Wave:** R50 tool
**Repo:** github.com/paideia-os/cat
**Upstream design:** `design/tooling/r49-r50-plan.md` §4.5 and §5.5
in [paideia-os](https://github.com/paideia-os/paideia-os), and
invariants D2 (semantic pipes), D3 (audit-first), and I4 (collapsed
exit-code vocabulary) in `design/tooling/plan.md`.

This document describes the internal shape of the `cat` reader. It
does not repeat the wave-level rationale from the paideia-os plan
doc; read that first for the D2 / D3 / I4 invariants and for why
`cat` is one of the six R50 P0 coreutils.

---

## 1. Public surface

`cat` is a tool binary, not a library. Its externally observable
surface is:

- **argv:** `cat [-n|-A|--schema] <file>...` reads each file in
  argv-order and writes its bytes to stdout. `cat --help` and
  `cat --version` follow the D3 standard flag vocabulary in
  `design/tooling/plan.md` I3. `cat` with zero positional files
  reads from stdin (KIND_IPC_ENDPOINT) — this path lands at
  M2-004.
- **stdout (text):** file bytes going verbatim to KIND_TTY(write);
  at M2 `-n` prefixes each line with its 1-based number and `-A`
  renders non-printable bytes with printable escapes.
- **stdout (schema):** if the file's `.pdxfs` metadata declares a
  schema, `cat` streams that schema's records on the semantic-pipe
  layer (M3-001). If no schema is declared, `cat` emits
  `RawByteChunk[]` records (offset + bytes) at 64 KiB granularity
  (M3-002). Both schemas are declared in `caps.decl` at M1 so
  consumers can inspect the manifest early.
- **stderr:** diagnostics (unreadable file, cap denied, sink
  overflow at M1).
- **exit codes** (per I4 in `design/tooling/plan.md` §4.2):
  - 0 — every file read and rendered successfully.
  - 2 — usage error (missing file, unknown flag, name too long).
  - 3 — system error (audit journal unreachable at M3+, render sink
    overflow at M1, file-read I/O error at M2+).
  - 4 — cap denied (no read cap for a named file's path).

Internally the binary is three modules at M1:

- `CatDispatch` (`src/argv_dispatch.pdx`) — argv parsing at M1
  (inline byte-scan; M2 migrates to `libpdx-argv` once its
  flag-arity API can express "-n and -A are boolean, do not
  consume argv[i+1]"). The parser stores parsed flag bits and up
  to `POS_MAX = 8` positional file pointers in the module's `.bss`
  singleton. Also carries the top-level dispatcher `cat_dispatch`
  and the alt entry `cat_dispatch_from_buf(buf, len)` used by
  tests and by the smoke fixture that predates R42 substrate.
- `FileRead` (`src/file_read.pdx`) — a file read stub. At M1
  returns `(0, 0)` unconditionally (file not found) because the
  R42 substrate (`KIND_PDXFS_FILE`) has not landed in the kernel
  at HEAD (2026-08-21) per `r49-r50-plan.md` §2.4. The return
  contract is `rax = src_buf_ptr` (0 = not found; non-zero at M2 =
  bytes read into a caller-visible buffer) with a `.bss` companion
  `file_src_len` carrying the byte-count. M2 replaces the body
  with a `KIND_PDXFS_FILE(read)` syscall wrapped by libpdx-cap;
  the return contract is preserved so the M2 patch is a
  body-only edit inside `file_read_stub`.
- `TtySink` (`src/tty_sink.pdx`) — a bounded write sink standing
  in for the M2 `KIND_TTY(write)` syscall. Backing store is a
  4 KiB `.bss` scratch buffer with a cursor; the byte count
  reached is exposed via `tty_out_len` for the M4 test harness.
  M2 replaces the sink with a real `KIND_TTY(write)` handoff via
  the shell's exec-time cap propagation; the sink's field names
  do not change, so the M2 patch is a leaf-function body edit.

The M1 sink exists so the alt entry `cat_dispatch_from_buf(buf,
buf_len)` can be exercised end-to-end from a test fixture without
depending on shell.M4's KIND_TTY handoff or on R42's
KIND_PDXFS_FILE substrate — both blockers today per
`r49-r50-plan.md` §2.4.

---

## 2. Argv grammar (M1-002)

The M1 grammar accepts:

```
argv     = argv[0] flag* positional+
flag     = "-n"                 # M2: prefix each line with its 1-based number
         | "-A"                 # M2: render non-printables with escapes
         | "--schema"           # M3: emit schema records on stdout
positional = <NUL-terminated bytes>    # a file path; max POS_MAX per invocation
```

Flags are boolean (arity 0). Any short flag with more than one
letter (e.g. `-nA`) is rejected as usage error 2 per the D3
one-per-hyphen contract (`design/tooling/plan.md` §3.4). Any long
flag not in the whitelist above is rejected as usage error 2.
Positionals are collected in argv-order into `pos_ptrs`. Zero
positionals is *valid* (stdin passthrough at M2-004); at M1 the
dispatcher treats zero positionals as usage error 2 until M2-004
lands the stdin path.

The M1 grammar limits are:
- `POS_MAX = 8` — the maximum number of file arguments per
  invocation. Exceeding this returns exit 2 (usage error). M2
  removes this cap as part of the streaming-read work.
- Flags are stored as a bit mask (`FLAG_N = 0x1`, `FLAG_A = 0x2`,
  `FLAG_SCHEMA = 0x4`). Storage is a single u64 in `.bss`; M4
  migrates to a caller-owned struct.

Migration to `libpdx-argv` (deferred to M2). libpdx-argv M1-002's
short-flag parser consumes `argv[i+1]` as a value if it does not
start with '-'. `cat -n foo.txt` under that semantics binds
`foo.txt` to `-n` as a value and leaves `pos_count == 0`, which
would be a user-facing bug. Migration waits for libpdx-argv M2's
declarative "these flags are boolean" API. The inline parser is
byte-for-byte compatible with what libpdx-argv-M2 will produce
(same `pos_ptrs` shape, same flag bit mask, same error codes) so
the M2 migration is a call-site swap, not a data-shape rewrite.

---

## 3. Dispatch pipeline

`cat_dispatch(argv, argc)` runs the following sequence:

1. `cat_reset()` — zero the parsed-state `.bss` slots.
2. `cat_parse_argv(argv, argc)` — walk argv; store flag bits into
   `flag_mask`; store positional file ptrs into `pos_ptrs`. On
   parse error, return exit 2.
3. If `pos_count == 0`, return exit 2 (usage error; M2-004 replaces
   this arm with the stdin passthrough).
4. For each positional file (M1: only the first is read; M2-001
   iterates all in argv-order): call `file_read_stub()`. At M1 the
   stub always returns `(0, 0)` → return exit 4 (cap denied).
5. If `file_read_stub()` returned a non-zero buffer pointer (M2+),
   call `tty_write_bytes(src_ptr, src_len)`. On sink overflow,
   return exit 3.
6. Return exit 0.

The alt entry `cat_dispatch_from_buf(buf, buf_len)` skips steps
1–4 and drives step 5 directly. It is used by M4 tests + the M1
smoke fixture (`cat_dispatch_from_buf` is the earliest end-to-end
runnable in this tree — it demonstrates the buf → sink pipeline
without needing R42 or shell.M4).

---

## 4. Storage model

All M1 state is `.bss`-singleton (one dispatch per process). The
`.bss` slots owned by the three modules are:

- `CatDispatch.flag_mask : u64` — the parsed flag bit mask.
- `CatDispatch.pos_ptrs  : [u64; 8]` — positional file ptrs.
- `CatDispatch.pos_count : u64` — number of positional entries.
- `CatDispatch.parse_error_arg_index : u64` — offending argv
  index on parse error (M4 diagnostic renderer).
- `FileRead.file_src_len : u64` — bytes returned by the M1 stub
  (always 0; M2 = real byte count).
- `TtySink.tty_out_buf : [u8; 4096]` — the sink scratch buffer.
- `TtySink.tty_out_len : u64` — the sink cursor / bytes-written
  running count.

M4 will migrate these to caller-owned structures once the
call-graph is stable.

---

## 5. paideia-as compliance

Every source file in this tree observes:

- Module name PascalCase basename, no directory prefix (per
  `feedback_paideia_os_loop_shape`).
- No `test` mnemonic; every zero-check is `cmp reg, 0`.
- Every `cmp reg, imm` uses immediate ≤ 0x7FFFFFFF (M1's largest
  are 8 for POS_MAX and 4096 for the sink cap).
- `r11` is scratch (paideia-as reserved); reloaded before every
  `.bss` read/write.
- Byte reads use `xor rax, rax; mov_b rax, [ptr]` (#1248
  mitigation).
- SysV push/pop parity: every non-leaf function pushes/pops the
  callee-save registers it touches, and `rsp % 16 == 0` at every
  nested call site.
- Instruction vocabulary stays inside the R49 reference-
  implementation subset: `add`, `and`, `or`, `xor`, `shl`, `shr`,
  `mov`, `mov_b`, `cmp`, `lea`, `call`, `ret`, `push`, `pop`,
  `jmp`, `je`, `jne`, `jge`, `jg`, `jl`, `jle`. No `sub` on
  general registers (the pkg main uses `sub rsp, 8` for stack-pad
  alignment which is a distinct case); no `not`, `neg`, `dec`,
  `inc`.

---

## 6. Cross-repo dependencies

- **paideia-os kernel:** `KIND_USER` (0x190, R48.M1), `KIND_TTY`
  (existing), `KIND_PDXFS_FILE` (R42, TBD — blocker), `KIND_IPC_
  ENDPOINT` (base 5, R20b). The R42 substrate is filed as
  paideia-os R42-PREP-001 through R42-PREP-003 per
  `r49-r50-plan.md` §5.0. Blocks cat.M1-003's real KIND_TTY sink
  and cat.M2's real KIND_PDXFS_FILE(read).
- **shell (paideia-os/shell):** cat.M1-003 declares the shell.M4
  KIND_TTY handoff dependency but stands in with the M1 sink
  until shell.M4 lands.
- **libpdx-argv (paideia-os/libpdx-argv):** cat.M2 migrates to
  libpdx-argv once its declarative flag-arity API lands (see §2).
- **libpdx-semantic-pipe:** cat.M3-001 depends on
  libpdx-semantic-pipe.M2 (schema-typed passthrough).
- **libpdx-audit:** cat.M3-003 depends on libpdx-audit.M2
  (FileReadRecord per file before first byte).

---

## 7. M1 non-goals

The following are M2+ and are deliberately not in M1:

- Real KIND_PDXFS_FILE(read) syscalls (blocked on R42 substrate).
- Real KIND_TTY(write) syscalls (blocked on shell.M4 handoff).
- Multi-file concatenation (M2-001 — M1 stops at the first file).
- `-n` line-number rendering (M2-002).
- `-A` non-printable rendering (M2-002).
- Streaming reads with 64 KiB chunks (M2-003).
- Stdin passthrough (M2-004).
- Schema-typed passthrough (M3-001).
- RawByteChunk[] emission (M3-002).
- FileReadRecord audit (M3-003).
- Signed release + `.pdxdoc` (M5-001).

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
  reads from stdin (KIND_IPC_ENDPOINT) — this path is exercised
  at M2-004.
- **stdout (text):** file bytes going verbatim to KIND_TTY(write);
  `-n` prefixes each output line with its right-justified 6-column
  line number followed by a tab; `-A` renders non-printable bytes
  with `^X` / `M-` / `$\n` escapes matching GNU cat -A = -vET.
- **stdout (schema):** if the file's `.pdxfs` metadata declares a
  schema, `cat` streams that schema's records on the semantic-pipe
  layer (M3-001). If no schema is declared, `cat` emits
  `RawByteChunk[]` records (offset + bytes) at 64 KiB granularity
  (M3-002). Both schemas are declared in `caps.decl` at M1 so
  consumers can inspect the manifest early.
- **stderr:** diagnostics (unreadable file, cap denied, sink
  overflow).
- **exit codes** (per I4 in `design/tooling/plan.md` §4.2):
  - 0 — every file read and rendered successfully.
  - 2 — usage error (missing file, unknown flag, name too long).
  - 3 — system error (audit journal unreachable at M3+, render
    sink overflow, file-read I/O error at R42+).
  - 4 — cap denied (no read cap for a named file's path).

Internally the binary is five modules at M2:

- `CatDispatch` (`src/argv_dispatch.pdx`) — argv parsing at M2
  (inline byte-scan; M3 migrates to `libpdx-argv` now that
  M2-001's FKIND_UNKNOWN=boolean fix removes the M1 blocker).
  The parser stores parsed flag bits and up to `POS_MAX = 8`
  positional file pointers in the module's `.bss` singleton.
  Also carries the top-level dispatcher `cat_dispatch` and the
  alt entry `cat_dispatch_from_buf(buf, len)` used by tests and
  by the smoke fixture that predates R42 substrate.
- `FileRead` (`src/file_read.pdx`) — streaming source layer:
  `file_open(path)` → handle; `file_read_chunk(handle, dst, cap)`
  → bytes read (≤ CHUNK_MAX = 65536); `file_close(handle)`. At
  M2 the bodies are a test-seedable stub (`file_read_seed_push`
  pre-loads canned sources; `file_open` draws handles in FIFO
  order; the seed cursor advances per read) because the R42
  substrate (`KIND_PDXFS_FILE`) has not landed in the kernel at
  HEAD per `r49-r50-plan.md` §2.4. Owns the shared 64 KiB
  `fr_chunk_buf` scratch used as the destination for both file
  and stdin reads. R42 replaces the bodies with `sys_pdxfs_open`
  / `sys_pdxfs_read` / `sys_pdxfs_close` wrappers via libpdx-cap
  and deletes the seed table; the four function signatures are
  invariant across the M2→R42 migration.
- `StdinSource` (`src/stdin_source.pdx`) — streaming stdin layer:
  `stdin_read_chunk(dst, cap)` → bytes read (0 = EOF). At M2 the
  body is a test-seedable stub (`stdin_seed(buf, len)` pushes a
  single source; the cursor advances per read) because the
  shell.M2 pipeline mint of the KIND_IPC_ENDPOINT frame carrier
  has not landed per `r49-r50-plan.md` §5.2. shell.M2 replaces
  the body with a `sys_ipc_recv` wrapper via libpdx-cap; the
  function signatures are invariant.
- `Render` (`src/render.pdx`) — the `-n` / `-A` transformation
  layer: `render_reset(flags)` initialises state (line counter =
  1, at-line-start = 1, flags stashed); `render_write_bytes(src,
  len)` iterates the source range byte-by-byte, emitting through
  `TtySink::tty_write_byte` with prefix (line number + tab) at
  each new line start when `-n` is set, and escape substitution
  when `-A` is set. Fast-path when neither flag is set: single
  `tty_write_bytes(rdi, rsi)` call — no per-byte overhead.
- `TtySink` (`src/tty_sink.pdx`) — a bounded write sink standing
  in for the M2 `KIND_TTY(write)` syscall. Backing store is a
  64 KiB `.bss` scratch buffer with a cursor; the byte count
  reached is exposed via `tty_out_len` for the M4 test harness.
  shell.M4 replaces the sink with a real `KIND_TTY(write)` handoff
  via the shell's exec-time cap propagation; the sink's field
  names do not change, so the shell.M4 patch is a leaf-function
  body edit inside `tty_write_bytes` + `tty_write_byte`. M2
  widens the cap from M1's 4 KiB to 64 KiB so the streaming path
  + render inflation can be exercised end-to-end.

The alt entry `cat_dispatch_from_buf(buf, buf_len)` bypasses
argv + file read + render — driving `TtySink::tty_write_bytes`
directly. It remains the simplest end-to-end fixture, useful for
smoke-checking the M2 sink cap.

---

## 2. Argv grammar (M1-002; preserved verbatim through M2)

The grammar accepts:

```
argv     = argv[0] flag* positional*
flag     = "-n"                 # M2: prefix each line with its 1-based number
         | "-A"                 # M2: render non-printables with escapes
         | "--schema"           # M3: emit schema records on stdout
positional = <NUL-terminated bytes>    # a file path; max POS_MAX per invocation
```

Flags are boolean (arity 0). Any short flag with more than one
letter (e.g. `-nA`) is rejected as usage error 2 per the D3
one-per-hyphen contract. Any long flag not in the whitelist is
rejected as usage error 2. Positionals are collected in
argv-order into `pos_ptrs`. **Zero positionals is valid** — the
M2-004 stdin path reads from `StdinSource::stdin_read_chunk`
until EOF.

Grammar limits:
- `POS_MAX = 8` — the maximum number of file arguments per
  invocation. Exceeding this returns exit 2. Matches
  `FileRead::SEED_MAX` so the M4 test harness can pre-seed
  one source per positional.
- Flags are stored as a bit mask (`FLAG_N = 0x1`, `FLAG_A = 0x2`,
  `FLAG_SCHEMA = 0x4`). Storage is a single u64 in `.bss`.

Migration to `libpdx-argv`: **now unblocked** by libpdx-argv
M2-001 (`FlagSpec::lookup` returns `FKIND_UNKNOWN = 0xFF` on
miss; the parser treats it identically to `FKIND_BOOL` so
`cat -n foo.txt` no longer binds `foo.txt` as `-n`'s value).
Migration is scheduled at cat.M3 per `r49-r50-plan.md` §5.5 so
the M2 wave stays byte-compatible with the M1 golden fixtures.
The inline parser is byte-for-byte compatible with what
libpdx-argv M2 produces (same `pos_ptrs` shape, same flag bit
mask, same error codes) so the M3 migration is a call-site
swap, not a data-shape rewrite.

---

## 3. Dispatch pipeline (M2)

`cat_dispatch(argv, argc)` runs the following sequence:

1. `cat_reset()` — zero parser state.
2. `cat_parse_argv(argv, argc)` — populate `flag_mask`,
   `pos_ptrs`, `pos_count`. On parse error, return exit 2.
3. `tty_reset()` — zero the sink cursor.
4. `render_reset(flag_mask)` — save flags, init line counter to
   1, mark at-line-start. Runs ONCE — line numbering is
   continuous across concatenated files (POSIX cat -n semantics).
5. Branch on `pos_count`:
   - `pos_count == 0` → **stdin path** (M2-004):
     ```
     loop:
       bytes = stdin_read_chunk(fr_chunk_buf, CHUNK_MAX)  # 65536
       if bytes == 0: break                                # EOF
       render_write_bytes(fr_chunk_buf, bytes) → check sink OK
     ```
   - `pos_count > 0` → **multi-file path** (M2-001):
     ```
     for i in 0..pos_count:
       handle = file_open(pos_ptrs[i])
       if handle == 0: return exit 4                       # cap denied / not found
       loop:
         bytes = file_read_chunk(handle, fr_chunk_buf, CHUNK_MAX)
         if bytes == 0: break                              # EOF this file
         render_write_bytes(fr_chunk_buf, bytes) → check sink OK
       file_close(handle)
     ```
6. Return exit 0 on clean completion; exit 3 on any sink overflow.

The alt entry `cat_dispatch_from_buf(buf, buf_len)` skips steps
1–5 and drives `tty_write_bytes` directly, bypassing the render
layer.

### 3.1 Streaming discipline

The 64 KiB `FileRead::fr_chunk_buf` scratch is the ONLY per-file
working memory the pipeline holds — a 1 GiB file streams through
16384 chunks; RAM never holds more than one chunk. This satisfies
r49-r50-plan.md §5.5 M2-003 ("never buffer full file; 64KiB
chunk"). The buffer is shared between the file and stdin sources
because M2 is not re-entrant: `cat_dispatch` drives sources
sequentially.

### 3.2 Test seedability

`cat_dispatch` does NOT call `file_read_reset` / `stdin_reset`
itself — those clear the M2 seed table which the M4 test harness
populates BEFORE dispatch. The harness pattern is:

```
file_read_reset()                          # or stdin_reset()
file_read_seed_push(a_buf, a_len)          # or stdin_seed(a_buf, a_len)
file_read_seed_push(b_buf, b_len)
...
cat_dispatch(argv, argc)                   # argv[1..] paths are ignored by the
                                           #   stub; the seed order maps 1-to-1
                                           #   onto the argv positional order.
```

Real R42 replaces the seed tables with `sys_pdxfs_open` /
`sys_ipc_recv` and deletes the M2 seed helpers; `cat_dispatch`'s
own control flow is invariant across the migration.

---

## 4. Storage model

All M2 state is `.bss`-singleton (one dispatch per process). The
`.bss` slots owned by the five modules are:

- `CatDispatch.flag_mask : u64` — parsed flag bit mask.
- `CatDispatch.pos_ptrs  : [u64; 8]` — positional file ptrs.
- `CatDispatch.pos_count : u64` — number of positional entries.
- `CatDispatch.parse_error_arg_index : u64` — offending argv
  index on parse error.
- `FileRead.fr_chunk_buf : [u8; 65536]` — shared streaming
  staging buffer (both file and stdin reads).
- `FileRead.fr_seed_bufs : [u64; 9]` — M2 seed table (bufs). Slot
  0 unused (invalid-handle sentinel).
- `FileRead.fr_seed_lens : [u64; 9]` — M2 seed table (lens).
- `FileRead.fr_seed_cursors : [u64; 9]` — per-handle read cursors.
- `FileRead.fr_seed_count : u64` — number of seeds pushed
  (0..SEED_MAX = 8).
- `FileRead.fr_next_handle : u64` — last handle issued by
  `file_open` (0..SEED_MAX).
- `StdinSource.sr_stdin_buf / sr_stdin_len / sr_stdin_cursor :
  u64` — single-source triple for the M2 stdin stub.
- `Render.render_flags : u64` — snapshot of flag_mask passed to
  render_reset.
- `Render.render_line_num : u64` — line counter (starts at 1).
- `Render.render_at_line_start : u64` — 0/1 flag: 1 = next
  non-EOF byte begins a new line and needs a prefix (when -n).
- `TtySink.tty_out_buf : [u8; 65536]` — sink scratch (M2 widened
  from M1's 4 KiB).
- `TtySink.tty_out_len : u64` — sink cursor / bytes-written
  running count.

`.bss` slot names in modules other than TtySink and CatDispatch
carry a module-scoped prefix (`fr_`, `sr_`, `render_`) to avoid
cross-repo unqualified-symbol collisions (mirrors the R48 vello↔
vrr `vrc_→vrenc_` rename policy in paideia-os).

M4 migrates these to caller-owned structures once the call-graph
is stable.

---

## 5. paideia-as compliance

Every source file in this tree observes:

- Module name PascalCase basename, no directory prefix (per
  `feedback_paideia_os_loop_shape`).
- No `test` mnemonic; every zero-check is `cmp reg, 0`.
- Every `cmp reg, imm` uses immediate ≤ 0x7FFFFFFF (M2's
  largest: 65536 for CHUNK_MAX / TTY_OUT_CAP; 100000 for the
  Render `10^5` digit-place).
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
  `jmp`, `je`, `jne`, `jge`, `jg`, `jl`, `jle`. **M2 addition:**
  `add reg, imm` with a NEGATIVE imm (e.g. `add rax, -100000`)
  is used in the Render layer for digit extraction — this encodes
  as `add reg64, imm8/imm32` with a sign-extended immediate,
  which paideia-as supports via `add_reg64_imm8` /
  `add_reg64_imm32` (see the encoder tests
  `add_reg64_imm8_negative_value` +
  `add_reg64_imm32_fitting_value`). The `sub` mnemonic is still
  avoided to stay byte-compatible with the M1 style ban.

---

## 6. Cross-repo dependencies

- **paideia-os kernel:** `KIND_USER` (0x190, R48.M1), `KIND_TTY`
  (existing), `KIND_PDXFS_FILE` (R42, TBD — blocker for
  file_read.pdx's real body), `KIND_IPC_ENDPOINT` (base 5,
  R20b — blocker for stdin_source.pdx's real body). The R42
  substrate is filed as paideia-os R42-PREP-001 through
  R42-PREP-003 per `r49-r50-plan.md` §5.0.
- **shell (paideia-os/shell):** shell.M4 KIND_TTY handoff still
  blocks the real TtySink; shell.M2 pipeline mint of
  KIND_IPC_ENDPOINT still blocks the real stdin path. cat M2
  stands in with test-seedable stubs; shell.M4 and shell.M2
  landings will replace the two stub bodies.
- **libpdx-argv (paideia-os/libpdx-argv):** libpdx-argv M2-001
  landed the FKIND_UNKNOWN=boolean fix that unblocks cat's
  migration. Migration scheduled at cat.M3.
- **libpdx-semantic-pipe:** cat.M3-001 depends on
  libpdx-semantic-pipe.M2 (schema-typed passthrough via
  `Passthrough::pipe_forward`).
- **libpdx-audit:** cat.M3-003 depends on libpdx-audit.M2
  (FileReadRecord per file before first byte).

---

## 7. M2 non-goals

The following are M3+ and are deliberately not in M2:

- Real KIND_PDXFS_FILE(read) syscalls (blocked on R42 substrate).
- Real KIND_TTY(write) syscalls (blocked on shell.M4 handoff).
- Real KIND_IPC_ENDPOINT stdin frames (blocked on shell.M2).
- Migration to libpdx-argv (unblocked by libpdx-argv M2-001;
  scheduled at cat.M3 for byte-compat with M1 fixtures).
- Schema-typed passthrough via `Passthrough::pipe_forward`
  (M3-001).
- RawByteChunk[] emission for schemaless files (M3-002).
- FileReadRecord audit via libpdx-audit (M3-003).
- Signed release + `.pdxdoc` (M5-001).

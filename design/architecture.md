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

Internally the binary is five modules at M2, extended to nine at
M3:

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

**M3 adds four modules to the binary:**

- `PipeOut` (`src/pipe_out.pdx`) — semantic-pipe frame emitter
  standing in for `libpdx-semantic-pipe`.
  `pipe_forward_frame(hash_ptr, body_ptr, body_len)` emits ONE
  R20b IPC frame with a 32-byte schema-hash prefix (op / ver /
  flags LE u16 / payload_len LE u32 = 32 + body_len; then hash
  bytes; then body bytes) through TtySink so the wire layout is
  observable to the M4 harness. `pipe_forward_write(hash_ptr,
  src_ptr, total_len)` sub-chunks src into ≤ SP_MAX_RECORD_BODY
  (4056) byte frames and emits one `pipe_forward_frame` per
  sub-chunk. When libpdx-semantic-pipe wires in (a shell.M2 +
  libpdx-semantic-pipe.M2 dependency chain), the frame emit path
  flips to `Send::send_frame` / `Passthrough::pipe_forward`; the
  two function signatures are invariant.
- `FileSchema` (`src/file_schema.pdx`) — per-handle
  schema-hash lookup stub. `file_schema_query(handle)` returns
  the 32-byte schema-hash pointer for a schema-declared file, or
  0 for schemaless. The M4 test harness pre-seeds the per-handle
  table via `file_schema_seed(handle, hash_ptr)`. R42's real
  `sys_pdxfs_getxattr(handle, "pdxfs.schema", ...)` replaces the
  stub body; the query signature is invariant.
- `RawByteChunk` (`src/raw_byte_chunk.pdx`) — schemaless-file
  fallback for the `--schema` path. Owns
  `_rbc_schema_hash : [u64; 4]` (RawByteChunk@0.1 placeholder
  fingerprint), `_rbc_file_offset : u64` (per-file byte offset,
  reset per file via `rbc_reset`), and
  `_rbc_scratch : [u8; 4056]` (record staging).
  `rbc_emit_chunk(src, len)` sub-chunks src into ≤ RBC_MAX_BODY
  (4048) byte records, each of the form
  `[offset:u64 LE | bytes]`, and emits one
  `PipeOut::pipe_forward_frame` per sub-chunk.
- `AuditStub` (`src/audit_stub.pdx`) — D3 audit-first gate stub
  for `libpdx-audit`. `audit_stub_file_read(path_ptr)` is an
  atomic begin+commit for one per-file FileReadRecord; the caller
  (`cat_dispatch`) checks the return before emitting any byte of
  that file's output. Broker unreachable → exit 3. The real
  libpdx-audit three-call sequence (`audit_begin` +
  `audit_record_output` + `audit_commit`) replaces the stub body
  when the `svc.audit-journal` broker binding lands; the
  `cat_dispatch` call site is invariant.

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

### 3.3 M3 pipeline extensions

Step 5 (the per-file loop) grows two new stages that land between
`file_open` and the M2 inner read loop:

```
for i in 0..pos_count:
  handle = file_open(pos_ptrs[i])
  if handle == 0: return exit 4                             # cap denied

  # ---- 5a: M3-003 audit-first gate ------------------------
  if audit_stub_file_read(pos_ptrs[i]) != 0:                # broker unreachable
    return exit 3                                           # D3: refuse to emit

  # ---- 5b: M3 schema branch -------------------------------
  if flag_mask & FLAG_SCHEMA:
    hash_ptr = file_schema_query(handle)
    if hash_ptr == 0:
      rbc_reset()                                            # per-file offset = 0
    loop:
      bytes = file_read_chunk(handle, fr_chunk_buf, CHUNK_MAX)
      if bytes == 0: break                                   # EOF this file
      if hash_ptr != 0:                                      # M3-001 passthrough
        if pipe_forward_write(hash_ptr, fr_chunk_buf, bytes) != 0:
          return exit 3
      else:                                                  # M3-002 RawByteChunk
        if rbc_emit_chunk(fr_chunk_buf, bytes) != 0:
          return exit 3
  else:                                                      # M2 render path
    loop:
      bytes = file_read_chunk(handle, fr_chunk_buf, CHUNK_MAX)
      if bytes == 0: break
      if render_write_bytes(fr_chunk_buf, bytes) != 0:
        return exit 3

  file_close(handle)
```

The audit call MUST land before any byte of the file's output
reaches TtySink — for the render path this is before the first
`render_write_bytes` call, and for both schema paths this is
before the first `pipe_forward_frame` (which is where any wire
byte ultimately hits the sink). The stdin path has no audit call
(no file to record); a future stdin/IPC-receive record is a
shell.M3 concern.

`rbc_reset` is called INSIDE the per-file loop on the schemaless
path so `_rbc_file_offset` re-zeros between files — each file's
first RawByteChunk record starts at offset 0.

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

M3 adds the following `.bss` slots (all with module-scoped
prefixes to sidestep cross-repo unqualified-symbol collisions):

- `FileSchema._fs_hash_ptrs : [u64; 9]` — per-handle schema-hash
  pointers. Slot 0 unused (invalid-handle sentinel); slots 1..8
  hold caller-supplied hash pointers or 0.
- `RawByteChunk._rbc_schema_hash : [u64; 4]` — 32-byte
  RawByteChunk@0.1 placeholder fingerprint installed by
  `rbc_reset`.
- `RawByteChunk._rbc_file_offset : u64` — per-file byte offset;
  advanced by `rbc_emit_chunk`, reset per file by `rbc_reset`.
- `RawByteChunk._rbc_scratch : [u8; 4056]` — record staging
  buffer holding [8B offset | up-to-4048B bytes].
- `AuditStub._audit_broker_failed : u64` — sticky broker-failure
  flag.
- `AuditStub._audit_file_count : u64` — monotonic count of
  successful per-file audit records (M4 observability).
- `AuditStub._audit_last_path_ptr : u64` — most recent per-file
  audit's path pointer (bookkeeping).

`.bss` slot names in modules other than TtySink and CatDispatch
carry a module-scoped prefix (`fr_`, `sr_`, `render_`, `_fs_`,
`_rbc_`, `_audit_`) to avoid cross-repo unqualified-symbol
collisions (mirrors the R48 vello↔vrr `vrc_→vrenc_` rename policy
in paideia-os).

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
- **libpdx-semantic-pipe:** cat.M3-001 ships a `PipeOut` stub
  whose wire format mirrors what `Passthrough::pipe_forward` /
  `Send::send_frame` will emit; the real library binding lands
  once libpdx-semantic-pipe.M2 + a downstream KIND_IPC_ENDPOINT
  are in place (shell.M2 concern). The two `pipe_forward_*`
  signatures are invariant across the migration.
- **libpdx-audit:** cat.M3-003 ships an `AuditStub` whose
  `audit_stub_file_read(path_ptr)` shape mirrors the real
  three-call sequence (`audit_begin` + `audit_record_output` +
  `audit_commit`). The `svc.audit-journal` broker binding lands
  once shell.M2 mints the endpoint cap; `cat_dispatch`'s per-file
  audit call site is invariant across the migration.

---

## 7. M4 correctness matrix

M4 ships four `.pdx` test modules under `tests/` — one per M4
issue in `design/tooling/r49-r50-plan.md` §5.5 — that exercise
the M3 pipeline through the stubs already in the src tree. Each
test module publishes exactly one entry function returning 0 on
PASS and a distinct non-zero exit code per assertion failure so
a driver harness can decode without inspecting logs.

| Test | Module | Fixture | Focus | Fail codes |
|------|--------|---------|-------|------------|
| M4-001 | `CatM4001` | 3 seed files (A/B/C, 4 bytes each) + argv[4] | multi-file argv-order preservation | 1..4 |
| M4-002 | `CatM4002` | 17-byte body + 32-byte 0xEE hash + argv=[cat, --schema, a] | R20b frame header + hash & body passthrough | 1..6 |
| M4-003 | `CatM4003` | 131072-byte source (= 2 × CHUNK_MAX) | streaming loop iterates > once; working set bounded | 1..4 |
| M4-004 | `CatM4004` | 6-byte stdin seed, argc=1 (zero positionals) | stdin path taken; audit NOT fired | 1..4 |

Every test uses the harness pattern documented at §3.2: reset →
seed → dispatch → assert on `TtySink::tty_out_buf` /
`tty_out_len` / `_audit_file_count`. Since paideia-as has no
data literals, every fixture byte / pointer is written at test
entry via `mov_b [ptr], rax` (byte-scoped) or `mov [ptr], rax`
(qword-scoped) after computing the address with `lea + add` —
same idiom as `TtySink::tty_write_bytes`.

**Load-bearing invariants covered by the matrix:**
- Argv-order preservation (M4-001).
- Audit-per-file count = argc-1 for the file path (M4-001).
- Schema-declared branch routes to `PipeOut::pipe_forward_write`
  and emits exactly one R20b frame with correct header +
  hash-prefix + body (M4-002).
- Schema branch also fires the audit-first gate (M4-002 asserts
  `_audit_file_count == 1` under `--schema`).
- Streaming loop iterates for source > `CHUNK_MAX`; working set
  bounded by `fr_chunk_buf` + `tty_out_buf` = 128 KiB regardless
  of source size (M4-003).
- Sink overflow propagates as `CAT_EXIT_SYSTEM_ERROR` (M4-003).
- Stdin path takes `pos_count == 0` branch and does NOT invoke
  `audit_stub_file_read` — no `StdinReadRecord` at cat.M4 (a
  future shell.M3 concern) (M4-004).
- Fast-path render passthrough is byte-exact when `flags == 0`
  (M4-004).

---

## 8. M4 non-goals

The following are M5+ and are deliberately not in M4:

- Real KIND_PDXFS_FILE(read) syscalls (blocked on R42 substrate).
- Real KIND_TTY(write) syscalls (blocked on shell.M4 handoff).
- Real KIND_IPC_ENDPOINT stdin frames (blocked on shell.M2
  pipeline mint).
- Real libpdx-semantic-pipe `Passthrough::pipe_forward` /
  `Send::send_frame` binding (blocked on libpdx-semantic-pipe.M2
  + downstream KIND_IPC_ENDPOINT). The stubbed
  `PipeOut::pipe_forward_*` still routes frames through TtySink
  so the wire bytes remain observable to the M4 matrix.
- Real libpdx-audit `audit_begin` + `audit_record_output` +
  `audit_commit` binding (blocked on the `svc.audit-journal`
  broker cap, a shell.M2 concern). `AuditStub` still collapses
  the three-call sequence into one atomic
  `audit_stub_file_read(path_ptr)` call.
- Real R42 `.pdxfs` schema-metadata lookup
  (`sys_pdxfs_getxattr(handle, "pdxfs.schema", ...)` or inline
  cap-descriptor field). `FileSchema` per-handle table is still
  test-seedable via `file_schema_seed` — M4-002 exercises this
  path.
- v1.0 RawByteChunk@0.1 canonical schema-hash fingerprint. The
  placeholder pattern (0x1111... / 0x2222... / 0x3333... /
  0x4444...) still ships in `rbc_reset`; v1.0 recomputes from the
  canonical schema DDL (tracked at cat.M5).
- Migration to libpdx-argv (unblocked by libpdx-argv M2-001;
  deferred pending a cross-repo pass on the argv shape).
- QEMU smoke harness that invokes the four `test_cat_m4_*` entry
  points from a bootable image (blocked on shell.M4 + the
  eventual paideia-os test driver; the M4 matrix itself is
  runnable today via any harness that can link the cat object
  files and call each test entry).
- Signed release + `.pdxdoc` + mirror push (M5-001, M5-002).

# cat.M4-001 — implementation notes

**Issue:** #11 — multi-file order-preservation test
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.5 (paideia-os).

## What landed

- `tests/m4_001_multi_file_order.pdx` — new `CatM4001` module:
  - Fixture `.bss` slots: three 4-byte source buffers (A/B/C, each
    ending in `\n`), three dummy path strings (`"a\0"`, `"b\0"`,
    `"c\0"` — content ignored by the M2 `FileRead` stub which draws
    handles FIFO), the tool-name string (`"cat\0"`), the argv[4]
    pointer array, and a 12-byte expected sink pattern.
  - `test_cat_m4_001_multi_file_order()` — non-leaf entry with a
    5-push callee-save prologue. Populates the fixtures at runtime
    (paideia-as has no data literals), resets the four stub tables
    (`FileRead` / `StdinSource` / `AuditStub` / `FileSchema`),
    pushes three seeds FIFO so handle N maps to argv positional N,
    calls `cat_dispatch(&argv, 4)`, and runs four assertions in
    order. Distinct non-zero exit codes per failure (1 = exit code
    mismatch, 2 = `tty_out_len` mismatch, 3 = audit count mismatch,
    4 = sink byte-sequence mismatch) let a driver harness decode
    which assertion tripped.

## Design decisions

**FIFO seed / argv-position mapping is what proves order.** The M2
`FileRead` stub ignores the argv path bytes (R42 will consume
them). Its `file_open` draws handles in FIFO order from the seed
table. So if `cat_dispatch` visits positionals in argv order (the
correctness invariant), sink content = `src_a || src_b || src_c` =
`"AAA\nBBB\nCCC\n"`. Any permutation bug — visiting the wrong
positional first, opening a handle before the previous file's
loop completes, or duplicating a handle — surfaces as a byte
mismatch at the first divergent scan index.

**Path strings must be non-empty and NUL-terminated.** The M2
`cat_parse_argv` routes any `argv[i]` starting with `-` into the
flag branches; a positional must have a leading non-`-` byte and
NUL-terminate within `NAME_MAX_LEN = 236`. Single-letter paths
(`"a\0"`, `"b\0"`, `"c\0"`) satisfy both. Content is ignored by
the stub but rejection at parse time would prevent the dispatch
from reaching the per-file loop.

**Fixture bytes are written per-byte at runtime.** paideia-as
declares `.bss` slots with `= uninit @align(8)`; there is no data
literal form. Every fixture byte is written with the `lea r11,
[rip + buf]; add r11, N; mov_b [r11], rax` idiom that mirrors
`TtySink::tty_write_bytes` — avoids `[base + reg]` byte-scale
addressing which has no precedent in the R49 reference
implementations.

**One audit per positional.** The M3-003 audit-first gate is
called inside the per-file loop, before `pipe_forward_frame` /
`render_write_bytes` ever hits `TtySink`. The `_audit_file_count
== 3` assertion catches both under-counting (dispatch skipped a
positional) and over-counting (dispatch double-audited a
positional).

## paideia-as conformance

- Module basename `CatM4001` (PascalCase); no directory prefix.
- No `test` mnemonic; every zero-check via `cmp reg, 0`.
- All `cmp reg, imm` immediates ≤ 0x7FFFFFFF (max 12).
- r11 scratch; reloaded before every `.bss` read/write.
- Byte reads use `xor rax, rax; mov_b rax, [ptr]` (#1248).
- Byte writes use the `add`-adjust pattern.
- 5-push callee-save prologue (rbx = sink base, r12 = expected
  base, r13 = scan cursor, r14 = expected byte, r15 = pad) lands
  rsp%16 == 0 at every nested call site.
- `.bss` slot names prefixed `m4_001_` to sidestep cross-repo
  unqualified-name collisions.

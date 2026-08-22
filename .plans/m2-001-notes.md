# cat.M2-001 — implementation notes

**Issue:** #4 — multi-file concatenation (arg-order preserved)
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.5 (paideia-os).

## What landed

- `src/file_read.pdx` — full module rewrite. The M1
  `file_read_stub()` single-blob shape (returned `(ptr, len)` for
  one file) is replaced with a streaming open→read-chunk→close
  API so `cat_dispatch` can iterate over any number of positional
  file arguments and concatenate their contents.
  - New `FileRead::file_open(path_ptr) -> handle` returning a
    1-based handle (0 = not-found / cap-denied).
  - New `FileRead::file_read_chunk(handle, dst, cap) -> bytes`
    returning bytes copied (0 = EOF). Covered in M2-003 notes.
  - New `FileRead::file_close(handle) -> rc` (M2 no-op; R42
    releases the kernel handle).
  - New `FileRead::file_read_reset()` + `FileRead::file_read_
    seed_push(buf, len)` — M2 test-seedable-stub helpers for the
    M4 harness. R42 deletes these along with the whole seed
    table.
  - Slot-0-reserved indexing convention (arrays sized 9 with
    slot 0 unused) sidesteps `handle - 1` arithmetic — no
    negative `add reg, imm` needed inside `file_read_chunk`.
- `src/argv_dispatch.pdx` — `cat_dispatch` rewritten to loop
  over `pos_ptrs[0..pos_count]` in argv-order. For each file:
  `file_open` → 0 collapses to CAT_EXIT_CAP_DENIED (4); nonzero
  handle drives an inner streaming loop calling
  `file_read_chunk(handle, fr_chunk_buf, CHUNK_MAX)` and feeding
  each returned chunk to `render_write_bytes`. Loop exits at
  first zero-byte read (EOF); `file_close(handle)` runs before
  advancing. All positional files are read even when the sink
  starts approaching cap (up to the sink cap, then exit 3).
  - 5-push callee-save prologue (rbx / r12 / r13 / r14 / r15).
    rbx carries the current handle across the inner
    `file_read_chunk` calls; r14 is the outer file-loop index;
    r13 is the pos_count snapshot (reused from argc after
    parse).
  - `POS_MAX = 8` preserved from M1 (matches `FileRead::SEED_
    MAX = 8`); M4 fixtures fit in ≤ 8 files.

## Design decisions

**One shared 64 KiB chunk buffer, sequentially reused.** Both
`file_read_chunk` and `stdin_read_chunk` accept a caller-owned
destination pointer + cap; `cat_dispatch` always passes
`FileRead::fr_chunk_buf` as the destination. M2 is not
re-entrant — `cat_dispatch` drives sources sequentially — so
sharing a single 64 KiB `.bss` scratch across all sources is
safe. Post-M2 concurrent sources would need per-source staging;
softarch's Round 3 refinement notes this as a possible R50 M4
refactor (caller-owned buffers per shell/pipeline stage).

**Arg-order preservation is trivial, but arg-source binding needs
seed FIFO.** `cat_parse_argv` already stores positional pointers
in `pos_ptrs` in argv-order; the M4 harness seeds `FileRead`
sources in the same order via repeated `file_read_seed_push`
calls, and `file_open` draws handles FIFO-style. So argv[1]'s
path corresponds to seed_bufs[1], argv[2]'s to seed_bufs[2], etc.
At R42 the path-to-source binding becomes real: `sys_pdxfs_open`
consumes the path ptr for real, and the seed table disappears.

**`file_close` is a no-op at M2 with intentionally checked
return.** `cat_dispatch` ignores `file_close`'s return value.
When R42 wires the real `sys_pdxfs_close` and the syscall can
fail (e.g., writeback of dirty pages fails on a memory-mapped
segment), softarch's Round 3 will edit `cat_dispatch` to check
the return and collapse to CAT_EXIT_SYSTEM_ERROR. The current
M2 shape leaves the check-and-collapse as a body-only edit at
the R42 landing.

## paideia-as conformance

- All `.bss` slot names prefixed with `fr_` for the FileRead
  module — sidesteps unqualified-name cross-repo collisions
  (mirrors the R48 vello ↔ vrr `vrc_→vrenc_` policy).
- Slot-0-reserved handle indexing eliminates the need for
  `handle - 1` (which would have required either a negative
  `add reg, imm` or a `sub reg, imm` mnemonic).
- Every `cmp reg, imm` uses immediate ≤ 0x7FFFFFFF (largest:
  65536 for CHUNK_MAX; 8 for SEED_MAX; 236 for NAME_MAX_LEN).
- `file_read_chunk` uses a single push/pop of r12 for the
  seed_lens value that must survive potential nested calls; the
  M2 body is a leaf, but the push/pop keeps the layout ready
  for R42's syscall-wrapping body without churning the
  prologue.
- `cat_dispatch` 5-push prologue (rbx / r12 / r13 / r14 / r15)
  places rsp%16 == 0 at every nested call site.

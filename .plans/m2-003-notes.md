# cat.M2-003 — implementation notes

**Issue:** #6 — streaming read (never buffer full file; 64KiB chunk)
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.5 (paideia-os).

## What landed

- `src/file_read.pdx` — `FileRead::file_read_chunk(handle, dst,
  cap)` implements a bounded per-call byte transfer:
  `min(cap, CHUNK_MAX = 65536, remaining)`. Three cmp+jge
  guards enforce the min inside the copy loop rather than
  pre-computing (which would need `sub reg, reg` to compute
  `remaining = total - cursor`). Returns bytes actually copied
  (0 = EOF or bad handle).
- `src/stdin_source.pdx` — `StdinSource::stdin_read_chunk(dst,
  cap)` mirrors the file shape: same three cmp+jge guards, same
  CHUNK_MAX = 65536 cap, same 0=EOF return convention. This
  parity lets `cat_dispatch` drive both sources through
  identical per-chunk loops (the only branch is on pos_count at
  the top).
- `src/argv_dispatch.pdx` — `cat_dispatch`'s per-source loop is
  bounded-buffer streaming: after each `file_read_chunk` /
  `stdin_read_chunk` returns, the chunk is flushed through
  `render_write_bytes` immediately, then the next chunk read is
  called with `dst = fr_chunk_buf` again. Working set never
  exceeds the single 64 KiB `fr_chunk_buf` — a 1 GiB file
  streams through 16384 iterations, RAM per file capped at 64
  KiB.

## Design decisions

**64 KiB chosen matching the r49-r50-plan.md §5.5 M2-003 line.**
The exact number is not load-bearing — bounded memory is what
matters — but 64 KiB balances syscall amortisation (once R42
lands `sys_pdxfs_read` will benefit from batching) against L1/L2
cache footprint (fits comfortably in modern data caches).

**Shared 64 KiB `.bss` scratch, not per-source.** Both file and
stdin reads target `FileRead::fr_chunk_buf`. M2 is not
re-entrant (`cat_dispatch` drives sources sequentially), so
sharing is safe. Post-M2 concurrent-stream refactors (softarch
Round 3) will introduce per-source staging in caller-owned
buffers.

**Three cmp+jge guards inside the copy loop.** The alternative
— computing `bytes_to_copy = min(cap, CHUNK_MAX, remaining)`
BEFORE the loop — needs subtraction (`remaining = total -
cursor`) which is off-limits in this repo's paideia-as subset.
The per-iteration bound-check pattern is stateless (each iter
re-checks) and adds negligible overhead against the byte-copy
itself.

**No unbounded byte counts anywhere in the pipeline.** Every
call in the M2 chunk pipeline reports back a concrete byte
count — `file_read_chunk` / `stdin_read_chunk` return bytes
copied; `render_write_bytes` receives the same count and iterates
byte-by-byte. There is no path where cat can request or receive
"the whole file" as a single blob.

## paideia-as conformance

- Every `cmp reg, imm` in `file_read_chunk` and `stdin_read_
  chunk` uses immediate ≤ 0x7FFFFFFF (largest: 65536 for
  CHUNK_MAX).
- Byte reads use `xor rax, rax; mov_b rax, [r11]` after
  `lea r11, [r9 + r10*1]` (#1248 mitigation).
- Byte writes to the caller-owned destination use `lea r11,
  [rdi + rcx*1]; mov_b [r11], rax` — avoids `[base + reg]`
  byte-scale addressing form (matches doc's
  `DocRenderer::render_section` idiom).
- `file_read_chunk` uses a single `push r12` (r12 preserves
  seed_lens[handle] across the loop); the M2 stub body is a
  leaf, but the push/pop keeps the layout ready for R42's
  syscall body.
- `stdin_read_chunk` is a strict leaf; no push/pop parity to
  preserve.

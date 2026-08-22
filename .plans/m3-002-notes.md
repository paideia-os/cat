# cat.M3-002 — implementation notes

**Issue:** #9 — RawByteChunk[] emission for schemaless files
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.5 (paideia-os).

## What landed

- `src/raw_byte_chunk.pdx` — new `RawByteChunk` module (schemaless
  fallback for the `--schema` path):
  - `_rbc_schema_hash : [u64; 4]` — 32-byte RawByteChunk@0.1
    fingerprint placeholder (four qwords of the pattern
    0x1111... / 0x2222... / 0x3333... / 0x4444..., trivially
    spottable in a hex dump; recomputed at v1.0 from the
    canonical schema DDL).
  - `_rbc_file_offset : u64` — per-file byte offset, advanced
    after every emitted record; reset per file by `rbc_reset`.
  - `_rbc_scratch : [u8; 4056]` — record staging buffer holding
    [8B offset LE | ≤ 4048B bytes].
  - `rbc_reset()` — installs the placeholder hash pattern into
    `_rbc_schema_hash` and zeros `_rbc_file_offset`. Called by
    `cat_dispatch` at the top of every per-file RBC-path inner
    loop.
  - `rbc_emit_chunk(src, len)` — sub-chunks src into ≤ RBC_MAX_BODY
    (4048) byte records. For each sub-chunk: writes the current
    `_rbc_file_offset` LE u64 into `_rbc_scratch[0..8]`,
    byte-copies src into `_rbc_scratch[8..8+sub_len]`, then calls
    `PipeOut::pipe_forward_frame(&_rbc_schema_hash, &_rbc_scratch,
    8 + sub_len)` and advances `_rbc_file_offset` by `sub_len`.
  - `rbc_get_offset()` — M4 test-harness observability helper;
    returns `_rbc_file_offset`.
- `src/argv_dispatch.pdx` — `cat_dispatch`'s FLAG_SCHEMA-set
  branch now selects between two paths per file:
  - `file_schema_query(handle) != 0` → M3-001 schema-typed
    passthrough via `pipe_forward_write`.
  - `file_schema_query(handle) == 0` → M3-002 RawByteChunk
    emission via `rbc_emit_chunk`, preceded by a `rbc_reset` call
    to zero the per-file offset.

## Design decisions

**Per-file offset resets between files.** RawByteChunk records
carry an `offset : u64 LE` field naming the file byte offset of
the record's first byte. Each file's first record starts at
offset 0. `cat_dispatch` calls `rbc_reset` inside the per-file
loop before the first `rbc_emit_chunk` for that file so the
counter re-zeros. `_rbc_file_offset` is not part of the M4 seed
table — it's a live counter the emit path advances internally,
observable via `rbc_get_offset`.

**Sub-chunk body cap = SP_MAX_RECORD_BODY − 8.** Each record's
body is `[offset:u64 | bytes]` — the 8-byte offset field consumes
part of the 4056-byte frame body cap, leaving 4048 bytes for the
raw payload. A 65536-byte file read fans out into 17 records
(16 × 4048 = 64768, then a residue of 768 bytes).

**Byte-by-byte inner copy avoids `remaining` computation.**
`rbc_emit_chunk`'s sub-chunk sizing is implicit: the copy loop
increments both the src cursor (rbx) and a fresh sub_len counter
(r13) per byte, terminating when EITHER r13 hits 4048 OR rbx hits
src_end. This dodges the need to compute
`remaining = src_end - src_cursor` (which paideia-as's ban on
`sub` and lack of `add reg, -reg` would make awkward).

**Placeholder hash — recomputed at v1.0.** `_rbc_schema_hash` is
a deterministic 32-byte constant standing in for the
BLAKE3-truncated fingerprint of the RawByteChunk@0.1 schema
definition. Consumers keyed off the M3 placeholder value will
need to re-key when v1.0 recomputes from the canonical DDL —
this is called out at the top of `src/raw_byte_chunk.pdx` and
tracked at cat.M5.

## paideia-as conformance

- Module basename `RawByteChunk` (PascalCase); no directory
  prefix.
- No `test` mnemonic; every zero-check via `cmp reg, 0`.
- All `cmp reg, imm` immediates ≤ 0x7FFFFFFF (max 4048 for the
  RBC_MAX_BODY sub-chunk gate).
- r11 scratch; reloaded before every `.bss` read/write.
- Byte reads use `xor rax, rax; mov_b rax, [ptr]` (#1248).
- `rbc_reset` / `rbc_get_offset` are leaf. `rbc_emit_chunk` is
  non-leaf with a 5-push callee-save prologue (rbx / r12 / r13 /
  r14 / r15) landing rsp%16 == 0 at every nested
  `pipe_forward_frame` call site.
- `.bss` slot names prefixed `_rbc_` to sidestep cross-repo
  unqualified-name collisions.

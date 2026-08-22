# cat.M4-003 — implementation notes

**Issue:** #13 — large-file streaming test (>RAM, no OOM)
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.5 (paideia-os).

## What landed

- `tests/m4_003_large_file_streaming.pdx` — new `CatM4003` module:
  - Fixture `.bss`: 131072-byte source (= 2 × `CHUNK_MAX`) filled
    at test entry with 0x41 via a per-byte fill loop bounded by
    `cmp rcx, 131072`; `"cat\0"` and `"a\0"` name strings; the
    2-slot argv pointer array.
  - `test_cat_m4_003_large_file_streaming()` — non-leaf entry
    with a 5-push callee-save prologue. Resets stub tables, seeds
    one FileRead source of 131072 bytes, calls
    `cat_dispatch(&argv, 2)`, and asserts the expected
    overflow-on-iter-2 outcome: exit = 3, `tty_out_len` = 65536
    (sink filled to `TTY_OUT_CAP` — proves iter 1 completed
    fully), audit count = 1, and three sink-byte samples (offsets
    0 / 32768 / 65535) all == 0x41.

## Design decisions

**"No OOM" reduces to two observable facts under the M2 stub
tree.** Fact (a): the only 64 KiB scratches are `fr_chunk_buf`
(source-side) and `tty_out_buf` (sink-side) — total .bss working
set is 128 KiB regardless of source size. Fact (b): the per-file
inner loop iterates at least twice for a source larger than one
chunk. The chosen fixture (131072 bytes = 2 × `CHUNK_MAX`) forces
exactly two chunk reads, and the intentional overflow on the
second iteration is what proves the loop iterated — an
implementation that whole-file-buffered would either OOM before
iter 1's read completed or would emit all 131072 bytes at once,
both impossible under `TTY_OUT_CAP = 65536`.

**Overflow-on-iter-2 is the expected outcome, not a bug.** The
sink cap in the M2 stub tree stands in for the future
`KIND_TTY(write)` handoff (shell.M4). With a real terminal there
is no per-write cap; the streaming loop would exit cleanly on
seed exhaustion (0-byte read from `file_read_chunk`), and the
`sample_at_offset` assertions would extend across the full 131072
bytes. Under the stub, we deliberately hit the sink cap to
observe that iteration 2 happened — an implementation that
skipped the streaming loop entirely would fail assertion 2
(sink length would be 0 or would be some smaller partial number).

**Audit fires before the read/emit loop.** Assertion 3
(`_audit_file_count == 1`) verifies that the M3-003 audit-first
gate fires even though the ultimate exit is a sink overflow —
the audit is atomic and runs BEFORE the first byte hits the
sink, so it succeeds even when the emit path later fails. This
also catches a class of bug where the audit call is moved inside
the render/schema branches (which would result in `_audit_file_
count == 0` because the overflow aborts before the atomic-commit
step).

**Sample offsets 0, 32768, 65535 cover the sink range.** A
byte-corruption bug that affected only the tail (e.g. a
per-chunk cursor bug bumped the sink pointer past the intended
tail) would surface at offset 65535 without touching offsets 0
or 32768. A full-scan (65536 comparisons) would be more
sensitive but adds ~65536 loop iterations; the 3-point sample
catches the two most likely fault modes (per-chunk boundary + tail
region) with negligible test runtime.

## paideia-as conformance

- Module basename `CatM4003` (PascalCase); no directory prefix.
- No `test` mnemonic; every zero-check via `cmp reg, 0`.
- All `cmp reg, imm` immediates ≤ 0x7FFFFFFF (max: 131072 for
  the fill-loop bound; 65535 for the sink-tail sample offset).
- r11 scratch; reloaded before every `.bss` read/write.
- Byte reads use `xor rax, rax; mov_b rax, [ptr]` (#1248).
- 5-push callee-save prologue (rbx = sink base, r12 = sample-
  offset scratch, r13/r14/r15 = pad) lands rsp%16 == 0 at every
  nested call site.
- `.bss` slot names prefixed `m4_003_` to sidestep cross-repo
  unqualified-name collisions.

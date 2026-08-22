# cat.M4-002 — implementation notes

**Issue:** #12 — schema-typed passthrough against known-schema
fixture
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.5 (paideia-os).

## What landed

- `tests/m4_002_schema_passthrough.pdx` — new `CatM4002` module:
  - Fixture `.bss`: 17-byte body (padded to 24 for alignment), a
    32-byte schema hash (4-qword store of `0xEEEEEEEEEEEEEEEE`),
    `argv[0] = "cat\0"`, `argv[1] = "--schema\0"`, `argv[2] =
    "a\0"`, and the 3-slot argv pointer array.
  - `test_cat_m4_002_schema_passthrough()` — non-leaf entry with a
    5-push callee-save prologue. Populates fixtures at runtime,
    resets stub tables, seeds one FileRead source (handle 1 → 17
    body bytes) and one FileSchema entry (handle 1 → &hash),
    calls `cat_dispatch(&argv, 3)`, and runs six assertions in
    order: exit code, `tty_out_len` = 57, audit count = 1, header
    byte pattern, hash-bytes-all-0xEE scan, body-bytes-all-0x42
    scan.

## Design decisions

**Sink layout mirrors `PipeOut::pipe_forward_frame` wire format
exactly.** Expected 57 bytes = 8 (R20b header) + 32 (schema hash)
+ 17 (body). Header bytes: `op = 0x01`, `ver = 0x01`, `flags LE
u16 = 0x0001`, `payload_len LE u32 = 49 = 0x31` (matches
`SP_MAX_RECORD_BODY = 4056` not being reached by this 17-byte
body — one frame emitted, not sub-chunked). Any drift in
`pipe_forward_frame`'s header composition or hash/body-emit loop
surfaces as an assertion-4/5/6 failure with a distinct exit code.

**"All-0xEE hash" + "all-0x42 body" makes divergence trivially
localisable.** The hash uses a value (0xEE = `238`) that never
appears as a valid ASCII / header / flag byte in the frame; the
body uses `'B' = 0x42` which the header layout also never uses.
So the two scan loops surface a passthrough drift as a hex
mismatch at the first divergent offset — no false positives from
one region bleeding into the other.

**Seed FIFO order: only one file, one schema.** M4-001 covers
multi-file order-preservation. M4-002 keeps to a single file so
the schema-routing invariant is isolated: the assertion "sink
contains a frame, not raw bytes" only holds when
`file_schema_query(1)` returns the seeded pointer (not 0). If
schema seeding is silently dropped, `cat_dispatch`'s schema branch
falls through to `rbc_reset` + `rbc_emit_chunk`, which would
produce a 40-byte-header + offset-prefix frame with the placeholder
`0x1111...` hash — the sink length (57) and the header byte-scan
would both diverge immediately.

**Audit count = 1 covers the M3-003 gate under the schema branch.**
The schema branch and the render branch share the pre-emit
`audit_stub_file_read` call. Asserting `_audit_file_count == 1`
after the schema-branch dispatch confirms audit still fires on
the schema path (a body-only edit to move the audit call inside
the render branch would fail this assertion).

## paideia-as conformance

- Module basename `CatM4002` (PascalCase); no directory prefix.
- No `test` mnemonic; every zero-check via `cmp reg, 0`.
- All `cmp reg, imm` immediates ≤ 0x7FFFFFFF (max 57 for the
  sink-length check; 40 for the body-scan bound).
- r11 scratch; reloaded before every `.bss` read/write.
- Byte reads use `xor rax, rax; mov_b rax, [ptr]` (#1248).
- 5-push callee-save prologue (rbx = sink base, r12 = scan cursor,
  r13/r14/r15 = pad) lands rsp%16 == 0 at every nested call site.
- `.bss` slot names prefixed `m4_002_` to sidestep cross-repo
  unqualified-name collisions.

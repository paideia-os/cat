# cat — status

**Wave:** R50 (Wave 2)
**Current milestone:** M5-001 (dual-signed release + `.pdxdoc`) —
LANDED. M5-002 (mirror push) pending in this same M5 cycle. On M5
close cat is *released* per the milestone rubric (§5 in
`design/tooling/r49-r50-plan.md`).

## Milestone rollup

| ID              | Title                                                                    | State  |
|-----------------|--------------------------------------------------------------------------|--------|
| M1-001 (#1)     | scaffold + caps.decl (one KIND_PDXFS_FILE cap per file arg)              | LANDED |
| M1-002 (#2)     | argv surface via libpdx-argv (cat [-n|-A|--schema] <file>...)            | LANDED |
| M1-003 (#3)     | first runnable: single-file KIND_TTY output                              | LANDED |
| M2-001 (#4)     | multi-file concatenation (arg-order preserved)                          | LANDED |
| M2-002 (#5)     | -n line-numbering + -A non-printable rendering                          | LANDED |
| M2-003 (#6)     | streaming read (never buffer full file; 64KiB chunk)                    | LANDED |
| M2-004 (#7)     | stdin passthrough when argv empty (read from KIND_IPC_ENDPOINT)         | LANDED |
| M3-001 (#8)     | schema-typed passthrough: if file declares schema, forward records      | LANDED |
| M3-002 (#9)     | RawByteChunk[] emission for schemaless files                            | LANDED |
| M3-003 (#10)    | FileReadRecord via libpdx-audit per file, before first byte             | LANDED |
| M4-001 (#11)    | multi-file order-preservation test                                      | LANDED |
| M4-002 (#12)    | schema-typed passthrough against known-schema fixture                   | LANDED |
| M4-003 (#13)    | large-file streaming test (>RAM, no OOM)                                | LANDED |
| M4-004 (#14)    | stdin-piping test (a | cat | b through shell pipeline)                  | LANDED |
| M5-001 (#15)    | dual-signed manifest.pdxsig + CHANGELOG-1.0 + cat.pdxdoc + deps.list    | LANDED |
| M5-002 (#16)    | pkgs.paideia-os staging mirror push manifest + v1.0.0 tag               | OPEN   |

See `design/tooling/r49-r50-plan.md` §5.5 in paideia-os for the
full milestone breakdown (M1–M5) and cross-repo dependencies.

## Substrate posture

M4 ships four .pdx test modules under `tests/` that exercise the
M3 pipeline through the same test-seedable stubs the source tree
already exposes for R42 / shell.M2 / shell.M4 / libpdx-audit /
libpdx-semantic-pipe. The stubs remain in place:

- `FileRead` — `KIND_PDXFS_FILE` blocked on R42 substrate; the
  M2 seed table + FIFO handle allocator stands in for
  `sys_pdxfs_open` / `sys_pdxfs_read` / `sys_pdxfs_close`. M4
  tests seed via `file_read_seed_push`.
- `StdinSource` — `KIND_IPC_ENDPOINT` frame carrier blocked on
  shell.M2 pipeline mint; the M2 single-source triple stands in
  for `sys_ipc_recv`. M4-004 seeds via `stdin_seed`.
- `TtySink` — `KIND_TTY(write)` handoff blocked on shell.M4; the
  64 KiB `.bss` sink scratch stands in for the real syscall. M4
  tests observe correctness by scanning `tty_out_buf` +
  `tty_out_len`.
- `PipeOut` — libpdx-semantic-pipe `Passthrough::pipe_forward`
  blocked on the KIND_IPC_ENDPOINT downstream binding
  (shell.M2 + libpdx-semantic-pipe.M2); the M3 frame emitter
  writes through TtySink so the wire bytes remain observable to
  M4-002.
- `FileSchema` — `.pdxfs` schema metadata lookup blocked on R42
  (`sys_pdxfs_getxattr` or inline cap-descriptor field); the M3
  per-handle table is seeded by M4-002 via `file_schema_seed`.
- `AuditStub` — libpdx-audit `AuditClient::audit_begin` +
  `audit_record_output` + `audit_commit` blocked on the
  `svc.audit-journal` broker binding (a shell.M2 concern); the
  M3 stub collapses the three-call sequence into one atomic
  `audit_stub_file_read` call. M4 tests observe correctness via
  `audit_stub_get_count`.

Every M4 test uses the harness pattern documented at
`design/architecture.md` §3.2: reset the four stub tables → seed
the fixtures → call `cat_dispatch(argv, argc)` → assert on
`TtySink::tty_out_buf` / `tty_out_len` / `_audit_file_count`.
When the real substrates wire in, the seed helpers go away and
the test-side setup shrinks; the assertions on the sink /
audit-count remain valid because those are the correctness
invariants, not the plumbing.

## Test matrix

| Test | Fixture | Assertion focus | Distinct fail codes |
|------|---------|-----------------|---------------------|
| M4-001 | 3 files (A/B/C, 4 bytes each) | argv-order preserved in sink concatenation | 1..4 |
| M4-002 | 1 file (17 × 0x42) + 32-byte 0xEE hash + --schema | R20b frame layout + hash & body passthrough | 1..6 |
| M4-003 | 1 file (131072 × 0x41) — 2 × CHUNK_MAX | streaming loop iterates > once; working set bounded at 128 KiB | 1..4 |
| M4-004 | stdin seed "PIPED\n" (6 bytes), zero positionals | stdin path taken, audit NOT fired, byte passthrough | 1..4 |

Each test's entry function `test_cat_m4_00X_...` returns 0 on
PASS and a distinct non-zero exit code per assertion failure so
a driver harness can decode which assertion tripped without
inspecting logs.

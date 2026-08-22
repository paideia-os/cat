# cat — status

**Wave:** R50 (Wave 2)
**Current milestone:** M3 (schema-typed passthrough via `PipeOut` +
per-handle `FileSchema` lookup + `RawByteChunk[]` emission for
schemaless files + `FileReadRecord` audit-first gate via
`AuditStub`) — CLOSED. Audit-conformant per the milestone rubric
(§5 in `design/tooling/r49-r50-plan.md`). Ready for M4 (correctness
matrix + smoke fixtures + pre-release fuzzers).

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

See `design/tooling/r49-r50-plan.md` §5.5 in paideia-os for the
full milestone breakdown (M1–M5) and cross-repo dependencies.

## Substrate posture

M3 ships against test-seedable stubs for five substrate layers:

- `FileRead` — `KIND_PDXFS_FILE` blocked on R42 substrate; the
  M2 seed table + FIFO handle allocator stands in for
  `sys_pdxfs_open` / `sys_pdxfs_read` / `sys_pdxfs_close`.
- `StdinSource` — `KIND_IPC_ENDPOINT` frame carrier blocked on
  shell.M2 pipeline mint; the M2 single-source triple stands in
  for `sys_ipc_recv`.
- `TtySink` — `KIND_TTY(write)` handoff blocked on shell.M4; the
  64 KiB `.bss` sink scratch stands in for the real syscall.
- `PipeOut` — libpdx-semantic-pipe `Passthrough::pipe_forward`
  blocked on the KIND_IPC_ENDPOINT downstream binding
  (shell.M2 + libpdx-semantic-pipe.M2); the M3 frame emitter
  writes through TtySink so the wire bytes remain observable to
  the M4 harness.
- `FileSchema` — `.pdxfs` schema metadata lookup blocked on R42
  (`sys_pdxfs_getxattr` or inline cap-descriptor field); the M3
  per-handle table stands in via `file_schema_seed`.
- `AuditStub` — libpdx-audit `AuditClient::audit_begin` +
  `audit_record_output` + `audit_commit` blocked on the
  `svc.audit-journal` broker binding (a shell.M2 concern); the
  M3 stub collapses the three-call sequence into one atomic
  `audit_stub_file_read` call.

Every stub exposes the exact signature the real replacement will
expose; `cat_dispatch`'s control flow is invariant across every
M3-stub → real-substrate migration. See
`design/architecture.md` §3.2 for the M4 test-harness seeding
pattern.

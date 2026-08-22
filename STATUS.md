# cat — status

**Wave:** R50 (Wave 2)
**Current milestone:** M2 (multi-file concatenation + -n / -A
rendering + 64 KiB streaming reads + stdin passthrough) — CLOSED.
Ready for M3 (schema-typed passthrough via
`libpdx-semantic-pipe::pipe_forward` + `RawByteChunk[]` for
schemaless files + `FileReadRecord` via libpdx-audit + migration
to libpdx-argv now that M2-001 FKIND_UNKNOWN=boolean has landed).

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

See `design/tooling/r49-r50-plan.md` §5.5 in paideia-os for the
full milestone breakdown (M1–M5) and cross-repo dependencies.

## Substrate posture

M2 ships against test-seedable stubs for both `FileRead`
(`KIND_PDXFS_FILE` blocked on R42 substrate) and `StdinSource`
(`KIND_IPC_ENDPOINT` frame carrier blocked on shell.M2). The
function signatures are the same signatures the R42-landed
replacement will expose; `cat_dispatch`'s control flow is
invariant across the M2-stub → real-substrate migration. See
`design/architecture.md` §3.2 for the M4 test-harness seeding
pattern.

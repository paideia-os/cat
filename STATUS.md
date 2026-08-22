# cat — status

**Wave:** R50 (Wave 2)
**Current milestone:** M1 (design + skeleton) — CLOSED. Ready for
M2 (multi-file concatenation, -n / -A rendering, streaming reads at
64 KiB chunks, stdin passthrough) once R42 substrate + shell.M4
land per `r49-r50-plan.md` §2.4.

## Milestone rollup

| ID              | Title                                                                    | State  |
|-----------------|--------------------------------------------------------------------------|--------|
| M1-001 (#1)     | scaffold + caps.decl (one KIND_PDXFS_FILE cap per file arg)              | LANDED |
| M1-002 (#2)     | argv surface via libpdx-argv (cat [-n|-A|--schema] <file>...)            | LANDED |
| M1-003 (#3)     | first runnable: single-file KIND_TTY output                              | LANDED |

See `design/tooling/r49-r50-plan.md` §5.5 in paideia-os for the full
milestone breakdown (M1–M5) and cross-repo dependencies.

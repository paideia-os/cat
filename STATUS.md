# cat — status

**Current release:** v1.2.1-A (Wave L batch: #26 / #27 / #29 / #30 /
#31 — see the "Wave L" section below and `CHANGELOG.md`).

**Wave:** R50 (Wave 2)
**Current milestone:** M5 (dual-signed release + `.pdxdoc` +
mirror push) — CLOSED. `cat` is *released* at v1.0.0 per the
milestone rubric (§5 in `design/tooling/r49-r50-plan.md`).
Physical push to `pkgs.paideia-os` is deferred to T-INFRA-001
in the paideia-os meta repo; see `MIRROR.md` §1.

## Milestone rollup

| ID              | Title                                                                    | State  |
|-----------------|--------------------------------------------------------------------------|--------|
| M1-001 (#1)     | scaffold + caps.decl (one KIND_PDXFS_FILE cap per file arg)              | LANDED |
| M1-002 (#2)     | argv surface (cat [-n|-A|--schema] <file>...)                            | LANDED |
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
| M5-002 (#16)    | pkgs.paideia-os staging mirror push manifest + v1.0.0 tag               | LANDED |

See `design/tooling/r49-r50-plan.md` §5.5 in paideia-os for the
full milestone breakdown (M1–M5) and cross-repo dependencies.

**Correction (ENH-006, #18):** the M1-002 row above previously read
"argv surface **via libpdx-argv**". That was false — `cat_parse_argv`
(`src/argv_dispatch.pdx`) has always been a hand-rolled inline byte
scanner, and `deps.list` has always declared an empty v1.0 dep set.
See `design/architecture.md` §2 and `.plans/m1-002-notes.md` for the
libpdx-argv migration's actual status (still open, tracked as #25).

## Enhancement wave (v1.x)

Nine issues filed against `docs/enhancement-plan.md`'s findings.
Landed so far:

| ID       | #   | Title                                                          | State  |
|----------|-----|-----------------------------------------------------------------|--------|
| ENH-001  | #17 | `_start` + `cat.ld` linker script + linked `cat.elf`            | LANDED (partial — see note) |
| ENH-002  | #22 | Reconcile with monorepo src/user/cat.pdx: one canonical cat     | LANDED (v1.2.0-A) — resolution: satellite is master per `design/user/in-tree-vs-satellite-transition.md`; in-tree body is Phase-A bin_seeds substrate scheduled for Phase-C retirement |
| ENH-003  | #23 | stderr diagnostics on open failure / cap denial / I/O error    | LANDED (v1.1.1-A) |
| ENH-004  | #24 | TtySink 64 KiB output ceiling                                   | LANDED (v1.2.0-A) — removed by v1.1-A substrate flip: live path in `entry.pdx` byte-pumps `sys_read`/`sys_write` in 4 KiB chunks until EOF, no ceiling; `tty_sink.pdx` stub retired dead code |
| ENH-005  | #20 | Wire `--version`; strip `--help`; fix `--schema` text           | LANDED |
| ENH-006  | #18 | Correct the libpdx-argv claim in STATUS.md                      | LANDED |
| ENH-007  | #25 | libpdx-argv migration                                           | LANDED (v1.2.0-A) — deps.list declares `libpdx-argv >= 1.1.3`; `src/tool_ident.pdx` defines `PDX_TOOL_NAME` + `PDX_TOOL_VERSION` externs per Wave 6 hotfix contract; `cat_parse_argv` retired dead code; runtime Parser wire-in deferred to v1.1-C |
| ENH-009  | #19 | Raise `NAME_MAX_LEN` from 236 to 255                            | LANDED |
| —        | #28 | v1.1-A real-body extraction (retire M1-001 STUB)                | LANDED (v1.1.0-A; re-affirmed v1.2.0-A) — `entry.pdx` `_start` inlines real `sys_open`/`sys_read`/`sys_write`/`sys_close`; the nine-module dispatch tree is unreachable dead code |
| —        | #32 | QEMU end-to-end smoke — `cat FOO` prints `FOO` on stdout        | PLACEHOLDER (v1.2.0-A) — `tests/qemu_e2e_cat_smoke.sh` lands; live run blocked on bin_seeds Phase-B cutover (design doc §4) |

**ENH-001 note:** `tools/build.sh` now links every `src/*.o` into
`build-out/cat.elf` via `src/cat.ld`, and `src/entry.pdx` provides a
real `_start` (execve-ABI argv/argc read, `sys_exit` on return). This
closes the walk-back finding that the tree produced no linkable
artifact at all. It deliberately does NOT convert `FileRead` /
`TtySink`'s stub bodies to raw `sys_open`/`sys_read`/`sys_write`/
`sys_close` — that would bypass the `KIND_PDXFS_FILE` / `KIND_TTY`
capability model `caps.decl` commits to, which is exactly the "one
canonical cat" architecture question ENH-002 (#22) exists to decide
deliberately and cross-repo, not to pre-empt inside a linker-script
patch. Until ENH-002 resolves, `cat.elf` links but its file-I/O
pipeline remains stub-gated (`file_open` against an unseeded table
returns 0 → exit 4 for every real path). `--version` and the
usage-error path are real (no stub involved) because they bypass
`cat_dispatch` entirely.

Remaining open: ENH-008 (#21, RawByteChunk hash — needs the
canonical DDL hash value from libpdx-semantic-pipe, not yet
researched here). Every other enhancement-wave issue (#22 / #24 /
#25 / #28 / #32) closed in the v1.2.0-A Wave-B batch — see the
enhancement-wave table above and CHANGELOG.md v1.2.0-A entry.

## Wave L (v1.2.1-A) — #26 / #27 / #29 / #30 / #31

Five-issue cohort. See `CHANGELOG.md`'s v1.2.1-A entry for the full
per-issue write-up; this section tracks the two items with an
external-gate posture.

| ID   | Title                                              | State  |
|------|-----------------------------------------------------|--------|
| #26  | R90-XREPO.013.M3-002 caps.decl + adoption           | LANDED (partial — see note below) |
| #27  | SCHEMA-001 libpdx-schema-registry client wire        | LANDED (placeholder — see `src/schema_wire.pdx`) |
| #29  | v1.1-B semantic-pipe emission                        | LANDED |
| #30  | v1.1-C release closer (repurposed as v1.2.1-A)       | LANDED |
| #31  | errno-mapping fixture (7 diagnostic blobs)           | LANDED |

**#26 note (external-gate pending):** `caps.decl`'s `requires:` block
already carried the exact four kinds R90-XREPO.013.M3-002 calls for
(`KIND_USER` / `KIND_PDXFS_FILE` / `KIND_TTY` / `KIND_IPC_ENDPOINT`)
from its original R50 M1 landing — no manifest edit was needed to
reconcile, only the adoption note added at `caps.decl`'s tail. The
OTHER half of M3-002's scope — "wire the libpdx-cap helper at entry;
refuse to run if reconciliation narrows below required set" — is NOT
wired into `src/entry.pdx` and cannot land yet: it depends on
`.013.M1-002` (the libpdx-cap client helper, not shipped in any repo
at this writing) and `.013.M2-001` (shell's real exec-time
reconciliation). `paideia-os/shell#39` documents shell's own side of
M2-001 landing (CHANGELOG.md: "exec-time reconciliation framing in
sys_execve path"), but shell's own `src/exec.pdx` still marks step (3)
`cap_manifest_verify` as "DEFERRED (libpdx-cap not linked)" at HEAD —
the actual enforcement `caps.decl`'s own header comment describes
("the shell's exec-time cap_manifest_verify... refuses at the shell
side") does not run anywhere in the stack yet. Tracked here as
external-gate pending on both `.013.M1-002` and the non-stub half of
`.013.M2-001`; re-audit when either lands.

**#27 note:** `SchemaWire::libpdx_schema_registry_register` is a real,
linkable symbol (not a true `STB_WEAK` default — paideia-as 0.36 has
no weak-linkage mechanism, per `libpdx-argv`'s own precedent) whose
body unconditionally returns the placeholder id `0xE05AC000`. Runtime
link migrates to a real `libpdx-schema-registry` client once
paideia-os#2000 (the service itself, currently inert) lands.

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
| cat#31 | 7 fake_errno rows via `ErrnoCapture` fd-2 stand-in | errno-to-message dispatch matches `entry.pdx`'s `entry_open_err` cmp-chain + I/O-error sentinel | 1..7 |

Each test's entry function `test_cat_m4_00X_...` returns 0 on
PASS and a distinct non-zero exit code per assertion failure so
a driver harness can decode which assertion tripped without
inspecting logs.

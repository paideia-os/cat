# cat — CHANGELOG

All notable changes to this tool land here, per invariant §9.1 in
`design/tooling/plan.md` (paideia-os).

Version scheme: semver. `v1.0.0` is the first signed release; the
milestone-close rubric that governs the R49/R50 wave (see
`design/tooling/r49-r50-plan.md` §5 in paideia-os) requires M1
runnable, M2 core-implemented, M3 audit-conformant, M4 ship-testable,
M5 dual-signed released.

---

## v1.0.0 — 2026-08-22 (M5 close, first signed release)

First 1.0. Dual-signed manifest, `.pdxdoc` for `doc cat`, and mirror
staging manifest for `pkgs.paideia-os`.

### Added at M5

- `manifest.pdxsig` — dual-signed package manifest per plan.md §D4 +
  §6.2 + §6.3 + §6.4. Author + root ML-DSA-65 signature blocks are
  `PENDING` bytes until the v0.33-crypto toolchain tag + T-INFRA-002
  signing bot land; the sha2-256 content hashes are real over the
  shipped tree.
- `cat.pdxdoc` — the man-equivalent long-form doc file per invariant
  I7 §2, in the format the `doc` tool's M1-002 parser will read.
  This is the FIRST `.pdxdoc` to ship in the R49/R50 wave; its
  section-marker + `.POSIX-DIFF` callout shape is the working
  reference for the other 13 tool + 5 library repos' M5-001 issues.
- `deps.list` — required by plan.md §9.1; empty at v1.0 (every
  libpdx-* consumer site is an in-tree stub).
- `MIRROR.md` — staging-manifest declaration for the push into
  `pkgs.paideia-os/staging/cat/1.0/`, per plan.md §9.3 flow.
  Actual push is blocked on T-INFRA-001 (pkgs.paideia-os repository
  host); the manifest below is the payload that will be pushed.

### Rollup — landing history M1 through M4

**M1 — Design + skeleton (LANDED)**
- M1-001 (#1): scaffold + `caps.decl` (one KIND_PDXFS_FILE cap per
  file arg).
- M1-002 (#2): argv surface — `-n` / `-A` / `--schema` flags +
  `POS_MAX=8` positionals.
- M1-003 (#3): first runnable — file_read stub + TtySink + alt entry.

**M2 — Core implementation (LANDED)**
- M2-001 (#4): multi-file concatenation, arg-order preserved.
- M2-002 (#5): `-n` line-numbering + `-A` non-printable rendering.
- M2-003 (#6): streaming read (never buffer full file; 64 KiB chunk).
- M2-004 (#7): stdin passthrough when argv empty (KIND_IPC_ENDPOINT).

**M3 — Semantic-pipe + audit integration (LANDED)**
- M3-001 (#8): schema-typed passthrough — PipeOut + FileSchema
  modules.
- M3-002 (#9): `RawByteChunk[]` emission for schemaless files.
- M3-003 (#10): `FileReadRecord` audit-first gate + M3 wire-in.

**M4 — Tests + smoke matrix (LANDED)**
- M4-001 (#11): multi-file order-preservation test.
- M4-002 (#12): schema-typed passthrough test.
- M4-003 (#13): large-file streaming test (no OOM).
- M4-004 (#14): stdin-piping test.

**M5 — 1.0 signed release (THIS RELEASE)**
- M5-001 (#15): dual-signed release + `.pdxdoc`.
- M5-002 (#16): mirror push.

### Substrate posture at v1.0

Six of nine source modules ship with test-seedable stubs standing in
for kernel substrates not yet landed at HEAD:

- `FileRead` — stubs `sys_pdxfs_open` / `_read` / `_close` until
  R42 (KIND_PDXFS_FILE) lands.
- `StdinSource` — stubs `sys_ipc_recv` until shell.M2 pipeline mint
  binds KIND_IPC_ENDPOINT frame carriers.
- `TtySink` — stubs the KIND_TTY(write) syscall until shell.M4
  lands the terminal cap handoff.
- `PipeOut` — stubs libpdx-semantic-pipe's `Passthrough::pipe_forward`
  until KIND_IPC_ENDPOINT downstream binding lands.
- `FileSchema` — stubs the .pdxfs schema-metadata lookup until R42
  `sys_pdxfs_getxattr` (or inline cap-descriptor field) lands.
- `AuditStub` — stubs libpdx-audit's `audit_begin` +
  `audit_record_output` + `audit_commit` sequence until
  `svc.audit-journal` broker registers per R49-PREP-006.

The stub table is documented in STATUS.md ("Substrate posture") and
in each `src/*.pdx` module's file-header note. Migration to real
substrates preserves every function signature; the M4 assertions are
on observable I/O effects, not on which side of the stub boundary
the byte crossed.

### Signature refusal witness

`pkg install cat` at v1.0 refuses with exit 4 (cap denied per I4)
until BOTH signature blocks in `manifest.pdxsig` carry non-PENDING
bytes. The refusal is an invariant of the two-key policy in
plan.md §6.2, not a reviewer discretion.

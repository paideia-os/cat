# cat — CHANGELOG

All notable changes to this tool land here, per invariant §9.1 in
`design/tooling/plan.md` (paideia-os).

Version scheme: semver. `v1.0.0` is the first signed release; the
milestone-close rubric that governs the R49/R50 wave (see
`design/tooling/r49-r50-plan.md` §5 in paideia-os) requires M1
runnable, M2 core-implemented, M3 audit-conformant, M4 ship-testable,
M5 dual-signed released.

---

## v1.2.1-A — 2026-09-13 (Wave L batch: #26 / #27 / #29 / #30 / #31)

Five-issue cohort landing R90-XREPO cap-manifest reconciliation,
SCHEMA-001 schema-registry wiring, v1.1-B semantic-pipe emission, an
errno-mapping fixture, and this release itself.

### Closed

- **#26 (R90-XREPO.013.M3-002)** — `caps.decl` + adoption. Reconciled
  the existing `requires:` block (landed pre-adoption at R50 M1)
  against the M3-002 shape spec (`design/round-retrospectives/
  r90-xrepo-wave3-plan.md`) and found it already byte-for-byte the
  required four kinds (`KIND_USER` / `KIND_PDXFS_FILE` /
  `KIND_TTY` / `KIND_IPC_ENDPOINT`) — no `requires:` edit needed.
  - `caps.decl` — new comment block recording the adoption and
    naming the still-external-gated half of M3-002's scope (the
    libpdx-cap client helper wire-in + refuse-below-required-set
    behaviour, gated on `.013.M1-002` and `.013.M2-001`).
  - `STATUS.md` — Wave L section notes shell's own `src/exec.pdx`
    still marks `cap_manifest_verify` "DEFERRED (libpdx-cap not
    linked)" at HEAD, so the enforcement side of M3-002 stays
    external-gate pending regardless of `paideia-os/shell#39`'s
    landed (but stub-shaped) exec-time reconciliation framing.

- **#27 (SCHEMA-001)** — wire `libpdx-schema-registry` client
  (`RawByteChunk@0.1`).
  - `src/schema_wire.pdx` — new `SchemaWire` module.
    `libpdx_schema_registry_register(ddl_hash_ptr)` is a real,
    linkable placeholder (paideia-as has no `STB_WEAK` linkage per
    `libpdx-argv`'s own precedent) that unconditionally returns
    `CAT_SCHEMA_ID_PLACEHOLDER` (`0xE05AC000`); `schema_wire_
    register()` calls it with `RawByteChunk::_rbc_schema_hash`'s
    address and caches the result in `cat_schema_id`. Runtime link
    migrates to a real registry client when `libpdx-schema-registry`
    (paideia-os#2000) lands — only this file's placeholder body
    changes.

- **#29 (v1.1-B)** — semantic-pipe emission.
  - `src/pipe_emit.pdx` — new `PipeEmit` module. One best-effort
    `sys_semantic_send` (sysno 115) at the end of every cat
    invocation, carrying a 128-byte `CatPipeRecord@0.1`
    (`version`+`op` bit-packed, `bytes_written`, `schema_id`,
    `path_hash_lo`/`hi`, `timestamp_ticks`, 10-qword reserved —
    see the file header for the size reconciliation against the
    issue text's 9-qword reserved count, which sums to 120B not
    128B).
  - `src/entry.pdx` — new `rbp` accumulator (total bytes written
    this run) and one call site at `entry_done`, before `sys_exit`:
    resolves the last-processed path, refreshes `cat_schema_id` via
    `SchemaWire::schema_wire_register`, then calls
    `PipeEmit::pipe_emit_send`. Return value discarded (best-effort,
    matching `cp`'s `pipe_emit_copy_record` precedent).

- **#30 (v1.1-C release closer, repurposed)** — this release. `v1.1`
  was superseded by `v1.2.0-A` before #30 landed, so this closer
  ships as `v1.2.1-A` instead: `CHANGELOG.md` (this entry),
  `README.md`'s repository-layout version-string line, `manifest.
  pdxsig` (§1 version → 1.2.1, `git_tag` → `v1.2.1-A`, new
  content_hashes entries for `src/schema_wire.pdx` and
  `src/pipe_emit.pdx`, all `TBD-RECOMPUTED-AT-SIGN` per the standing
  substrate-gate posture — no signing bot yet), `src/tool_ident.pdx` /
  `src/entry.pdx`'s `entry_version_msg` bumped `1.2.0-A` → `1.2.1-A`.
  Tag `v1.2.1-A` lands from this commit's HEAD.

- **#31** — errno-mapping fixture: 7 diagnostic blobs fire from the
  correct trigger.
  - `tests/errno_capture.pdx` — new `ErrnoCapture` module. A
    `sys_write(2, ...)` capture stand-in (`ec_capture_write`) plus
    `ec_reset`, following the established M4 test-seedable-stub
    pattern (never links into `cat.elf`; compiles standalone).
  - `tests/cat_errno_map.pdx` — new `CatErrnoMap` module. Replicates
    `src/entry.pdx`'s `entry_open_err` cmp-chain (errno 2/5/13/14/1/
    default) plus a sentinel arm for the two non-errno-dispatched
    `cat_msg_ioerror` sites (mid-copy read failure, stdin read
    failure) — 7 rows total. `test_cat_errno_map_all` drives all
    seven via a module-level `fake_errno` cell, asserts the captured
    fd-2 bytes exactly match the golden `cat_msg_*` text snapshot,
    and returns 0 on PASS or 1..7 naming the first mismatched row.

---

## v1.2.0-A — 2026-09-13 (Wave-B batch: #22 / #24 / #25 / #28 / #32)

Minor bump consolidating five enhancement-wave issues into a single
release. No live-path behaviour change beyond the version-string
byte swap (`1.1.1-A` → `1.2.0-A`); the batch is dominated by
documentation, a new externs module for the libpdx-argv v1.1.3
contract, deps.list's first non-empty entry, and a QEMU smoke
placeholder. The v1.1-A substrate flip (real `sys_open`/`_read`/
`_write`/`_close` in `entry.pdx`) that closes #24 and #28 was
already landed at v1.1.0-A; this release re-affirms and
explicitly-closes those issues alongside the three
never-previously-landed items.

### Closed

- **#22 (ENH-002)** — Reconcile with monorepo `src/user/cat.pdx`:
  one canonical cat. Resolution: **satellite is master** per
  `design/user/in-tree-vs-satellite-transition.md` (Wave 18) §3.
  The in-tree body is Phase-A `bin_seeds` substrate scheduled for
  Phase-C retirement once the satellite build product is wired
  into `tools/bin_seeds.manifest`. No code change in this
  satellite; STATUS.md's enhancement-wave table records the
  design-doc pointer.

- **#24 (ENH-004)** — Remove TtySink 64 KiB output ceiling. The
  ceiling was a live-path failure mode in the v1.0 dispatch tree
  where every write funneled through `TtySink::tty_write_bytes`
  and refused past `TTY_OUT_CAP = 65536`. The v1.1-A substrate
  flip retired that path: `entry.pdx` `_start` byte-pumps
  `sys_read(fd, cat_buf, 4096)` → `sys_write(1, cat_buf, n)`
  in a loop until `rax == 0` (EOF) with no intermediate buffer
  and no cap. A 1 GiB file cats through `cat_buf` (4 KiB) in
  262144 syscall pairs — no OOM, no ceiling.
  - `src/tty_sink.pdx` — file-header note added: module is dead
    code post-v1.1-A; cited from the entry.pdx retired-modules
    list. The `TTY_OUT_CAP = 65536` constant + `tty_out_buf`
    sizing are UNCHANGED because `tests/*.pdx` fixtures still
    reference them (fixtures compile but never link into
    cat.elf so the constants have no shipped-binary effect).

- **#25 (ENH-007)** — Migrate `cat_parse_argv` to libpdx-argv.
  - `src/tool_ident.pdx` — new module. Defines the two
    `.rodata` externs required by libpdx-argv v1.1.3
    `VersionBackend::emit_default` per the ENH-032 hotfix
    contract (paideia-os/libpdx-argv #42):
      - `PDX_TOOL_NAME    : [u8; 4] = "cat\0"`
      - `PDX_TOOL_VERSION : [u8; 8] = "1.2.0-A\0"`
  - `deps.list` — first non-empty entry: `libpdx-argv >= 1.1.3`.
    Declares the dep now (before the runtime wire-in) so
    `pkg install cat` pre-stages libpdx-argv into the shared-lib
    closure and the v1.1-C `Parser::parse_argv` symbol swap is
    a rebuild-only landing.
  - `src/argv_dispatch.pdx` — file-header note added: the
    hand-rolled `cat_parse_argv` byte scanner is retired dead
    code post-v1.1-A (`_start` handles argv directly with a
    10-byte inline `--version` compare); the runtime Parser
    wire-in is deferred to v1.1-C at which point this whole
    module is removable alongside the sibling stub cleanups.
  - `manifest.pdxsig` — §1 version bumped to 1.2.0; §3 deps.list
    sha2-256 witness set to `TBD-RECOMPUTED-AT-SIGN`; §4
    content_hashes gain three entries (`src/entry.pdx`,
    `src/cat.ld`, `src/tool_ident.pdx`) all marked
    `TBD-RECOMPUTED-AT-SIGN` per the same substrate-gate posture
    as v1.0.

- **#28** — v1.1-A real-body extraction. **Already landed at
  v1.1.0-A** (commit `6a4cbf7`); this release explicitly
  re-affirms the close in STATUS.md's enhancement-wave table.
  `entry.pdx` `_start` inlines the four SC+ syscalls it needs
  (read=0, write=1, open=2, close=3, exit=60) directly rather
  than calling `cat_dispatch`; the nine-module dispatch tree
  (`argv_dispatch.pdx` / `file_read.pdx` / `tty_sink.pdx` /
  `stdin_source.pdx` / `render.pdx` / `audit_stub.pdx` /
  `file_schema.pdx` / `pipe_out.pdx` / `raw_byte_chunk.pdx`) is
  unreachable dead code. See the entry.pdx header note
  "Retired stub modules (unreachable dead code post-v1.1-A)".

- **#32** — QEMU end-to-end smoke — `cat FOO` prints `FOO` on
  stdout. Placeholder driver script lands.
  - `tests/qemu_e2e_cat_smoke.sh` — new. Locates the paideia-os
    monorepo root, verifies the bin_seeds satellite cutover
    manifest is present + routes `/bin/cat` to satellite,
    builds `cat.elf` locally, invokes `run-qemu.sh` with a
    boot-cmd seeding `/tmp/FOO` with `FOO\n` and executing
    `cat /tmp/FOO`, greps the captured serial log for `^FOO$`.
    Exit codes: 0 PASS, 1 FAIL, 77 SKIP (autotools convention).
    All three preconditions are currently unmet at HEAD
    (bin_seeds Phase-B not landed, tools/bin_seeds.manifest
    does not exist) so a run yields SKIP: with a diagnostic
    pointing at `design/user/in-tree-vs-satellite-transition.md`
    §4 Phase-B. Actual live PASS is a downstream event.
  - `tests/README.md` — matrix row added noting the smoke's
    non-M4 posture (whole boot→shell→exec chain, not a module
    contract in isolation).

### Version string bump

- `src/entry.pdx::entry_version_msg` — 25-wire-byte literal
  updated `cat (paideia-os) 1.1.1-A\n` → `cat (paideia-os)
  1.2.0-A\n`. Same length, same layout, no encoder risk.

### Not touched

- No functional change to `entry.pdx` `_start` body, register plan,
  errno dispatch, or diagnostic composer. `entry_strlen_nul` /
  `entry_emit_diag` / `_start`'s SysV frame all unchanged.
- No change to `caps.decl` (still one `KIND_PDXFS_FILE` per file
  arg per invariant I6).
- No change to `cat.pdxdoc` (the flag-layer resurrection scheduled
  for v1.1-B / v1.1-C is where the pdxdoc updates re-fire).
- Signatures in `manifest.pdxsig` §6 + §7 remain `PENDING` bytes
  — the T-INFRA-002 signing bot + paideia-as v0.33-crypto tag are
  still not reachable from HEAD; every hash rehash + signature
  emit is a downstream event.

### Substrate posture at v1.2.0-A

Unchanged from v1.1.0-A: the retired stub tree in
`src/{argv_dispatch,file_read,tty_sink,stdin_source,render,
audit_stub,file_schema,pipe_out,raw_byte_chunk}.pdx` compiles + links
into `cat.elf` but is never reached at run time. Live path is
_start's inline byte pump; the v1.1-B / v1.1-C follow-ups (flag
layer resurrection over the real substrate + libpdx-argv Parser
wire-in) are where the removal batch fires.

### Fingerprint

- `cat --version` → `cat (paideia-os) 1.2.0-A\n` on fd 1, exits 0.
- `cat /nonexistent` → `cat: /nonexistent: No such file or
  directory\n` on fd 2, exits 1 (v1.1.1-A ENH-003 preserved).
- `bash tests/qemu_e2e_cat_smoke.sh` → exit 77 (SKIP) at HEAD;
  exit 0 (PASS) once Phase-B bin_seeds cutover lands.

---

## v1.1.1-A — 2026-09-12 (ENH-003 stderr diagnostics)

Patch release closing enhancement-v1.x issue #23 (`cat.ENH-003`).
The v1.1.0-A silent-failure hole is closed: cat now emits
`cat: <path>: <reason>\n` on fd 2 for every failure mode and exits
with `0` iff every source succeeded, `1` otherwise (POSIX `cat`
convention). Replaces v1.1.0-A's collapse-every-failure-to-`not
found`-then-`exit(0)` posture.

### Landed

- **cat.ENH-003 (issue #23)** — per-mode stderr diagnostics + POSIX
  exit code.
  - `src/entry.pdx`
    - Retired the single `: not found\n` suffix. Replaced it with
      an errno-mapped `.rodata` table and a mid-copy read-failure
      blob:
      - `cat_msg_enoent`  — `: No such file or directory\n` (-ENOENT)
      - `cat_msg_eio`     — `: Input/output error\n`        (-EIO)
      - `cat_msg_eacces`  — `: Permission denied\n`         (-EACCES)
      - `cat_msg_efault`  — `: Bad address\n`               (-EFAULT)
      - `cat_msg_eperm`   — `: denied by capability policy\n` (-EPERM,
                            the reserved wording for any future
                            `sys_cap_invoke` cap denial — distinct
                            from EACCES, which is filesystem-level
                            permission, not capability policy)
      - `cat_msg_unknown` — `: unknown error\n`             (default)
      - `cat_msg_ioerror` — `: I/O error\n`                 (sys_read
                            failure mid-copy)
      - `cat_stdin_path`  — `<stdin>` pseudo-path for the stdin-read
                            error branch
    - Added `entry_strlen_nul(ptr) -> len` leaf helper — same shape
      as rm 1.0.1's `Print::strlen_nul` and mkfs.pdxfs's
      `format_record_strlen`. Used by the diagnostic composer to
      compute path length without repeating the inline byte-loop.
    - Added `entry_emit_diag(path, msg_ptr, msg_len)` composer —
      three fd-2 `sys_write`s (`cat: ` prefix + path + msg blob).
      3-push callee-save prologue keeps `rsp % 16 == 0` at the
      nested `entry_strlen_nul` call site.
    - `_start` rewrite: `sub rsp, 8` alignment prologue for the
      new `call entry_emit_diag` sites (execve delivers `rsp%16==8`
      per rm/main.pdx precedent). `xor rbx, rbx` initialises the
      `had_error` flag; every failure path sets `rbx = 1`. Errno
      dispatch negates `rax` via `xor rcx,rcx; sub rcx, rax; mov
      rax, rcx` (no `neg` mnemonic — avoids paideia-as encoder
      ambiguity), then walks a `cmp`-chain against positive errno
      constants (2 / 5 / 13 / 14 / 1). Sys_read return now
      distinguishes `n == 0` (clean EOF) from `n < 0` (I/O error);
      the error branch calls `entry_emit_diag` with `cat_msg_ioerror`
      before falling through to `sys_close`. Stdin-read path gains
      the same distinction with `cat_stdin_path` as the pseudo-path.
      Final `sys_exit(rbx)` yields `0` on clean and `1` on any
      diagnostic.
    - `entry_version_msg` bumped `1.1.0-A` → `1.1.1-A` (25 wire
      bytes preserved).
  - Encoder discipline held throughout:
    - No `test rN` (every zero-check is `cmp reg, 0`).
    - No 2-op `imul r, imm`.
    - No `and r11, imm64`.
    - No `neg` mnemonic (errno negation via `xor + sub`).
    - Every `cmp reg, imm` immediate ≤ 4096 (SC+ IDs 0-60, argc
      guards, byte-value compares, positive errno constants ≤ 14).
    - Every string literal on a single line
      (tools/verify-fingerprint-coverage.sh extractor requirement).
    - Every label prefixed `entry_` (paideia-as reserved-word
      discipline; `loop` is a keyword).
    - Byte loads use `xor rax,rax; mov_b rax, [ptr]` (#1248
      mitigation).

### Fingerprint

- `cat /nonexistent` writes `cat: /nonexistent: No such file or
  directory\n` to fd 2 and exits `1`.
- `cat /root/perm-denied` writes `cat: /root/perm-denied: Permission
  denied\n` (or `denied by capability policy\n` for a cap-gated
  refusal) to fd 2 and exits `1`.
- `cat /dev/read-fails` (successful open, read fails) writes what
  was already copied to fd 1, then `cat: /dev/read-fails: I/O
  error\n` to fd 2, closes the fd, and continues to the next
  positional; the whole invocation exits `1`.
- `cat existing missing` writes `existing`'s contents to fd 1, then
  `cat: missing: No such file or directory\n` to fd 2, exits `1`.
- `cat existing` (every source succeeds) exits `0` — unchanged.

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

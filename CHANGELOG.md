# cat — CHANGELOG

All notable changes to this tool land here, per invariant §9.1 in
`design/tooling/plan.md` (paideia-os).

Version scheme: semver. `v1.0.0` is the first signed release; the
milestone-close rubric that governs the R49/R50 wave (see
`design/tooling/r49-r50-plan.md` §5 in paideia-os) requires M1
runnable, M2 core-implemented, M3 audit-conformant, M4 ship-testable,
M5 dual-signed released.

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

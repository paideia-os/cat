# cat.M3-003 — implementation notes

**Issue:** #10 — FileReadRecord via libpdx-audit per file, before
first byte
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.5 (paideia-os).

## What landed

- `src/audit_stub.pdx` — new `AuditStub` module (D3 audit-first
  gate stub for libpdx-audit):
  - `_audit_broker_failed : u64` — sticky failure flag. Once set,
    every subsequent `audit_stub_file_read` returns
    AS_ERR_BROKER_UNAVAIL and every `audit_stub_can_emit` returns
    0. Test-seedable via `audit_stub_seed_broker_failure`.
  - `_audit_file_count : u64` — monotonic count of successful
    per-file audit records. M4 asserts this equals the number of
    file arguments cat processed.
  - `_audit_last_path_ptr : u64` — bookkeeping slot recording the
    most recent per-file audit's path pointer.
  - `audit_stub_reset()` — zeros all three slots.
  - `audit_stub_file_read(path_ptr)` — atomic begin+commit for
    one per-file FileReadRecord. Returns AS_OK (0) on success or
    AS_ERR_BROKER_UNAVAIL (1) on broker unreachable — caller MUST
    exit 3 per D3 audit-first.
  - `audit_stub_can_emit()` — returns 1 iff safe to emit output,
    0 if the sticky flag is set. Mirrors
    `AuditClient::audit_can_emit_output` in libpdx-audit.
  - `audit_stub_seed_broker_failure(flag)` — M4 test-harness
    helper. Real libpdx-audit has no such seed.
  - `audit_stub_get_count()` — M4 observability helper; returns
    `_audit_file_count`.
- `src/argv_dispatch.pdx` — `cat_dispatch`'s per-file loop gains
  a stage 5a `audit_stub_file_read(pos_ptrs[i])` call, landing
  AFTER `file_open` succeeds but BEFORE any byte of the file's
  output reaches the sink (which for the schema-typed and
  RawByteChunk paths means before the first
  `pipe_forward_frame` write hits TtySink, and for the
  render-text path means before the first `render_write_bytes`
  call). Broker unreachable → CAT_EXIT_SYSTEM_ERROR (3).

## Design decisions

**Audit-first is a non-optional gate.** If the audit journal is
unreachable or full, `cat` refuses to emit output — the D3
upgrade of I5 (§3 in design/tooling/plan.md) treats "a tool that
can suppress its own audit trail" as an attack surface. This is
enforced by the pre-emit `audit_stub_file_read` call in
`cat_dispatch`: any non-zero return collapses to exit code 3.

**Atomic per-file "record" — stub-only simplification.** The real
libpdx-audit sequence is `audit_begin("cat_file_read", args)` →
`audit_record_output(id, "FileReadRecord@0.1", body_hash)` →
`audit_commit(id, 0)`. The stub collapses that into one call
because it carries no in-flight audit state per call. When
libpdx-audit wires in, `audit_stub_file_read`'s body flips to
three real library calls; `cat_dispatch`'s per-file audit call
site is invariant across the migration.

**Stdin path deliberately has no audit.** The audit call sits
inside the per-file (`pos_count > 0`) branch. The stdin path
(`pos_count == 0`) has no file, so no FileReadRecord is
appropriate — a future StdinReadRecord (or IPCReceiveRecord) is
a shell.M3 concern (shell.M3-003 `ShellCommandRecord`), not
cat's.

**Broker failure is sticky.** Once `_audit_broker_failed` is set,
every subsequent `audit_stub_file_read` fails-fast without
incrementing the file count. This models what a real IPC-send
failure would look like: the audit journal is offline, and cat's
per-file loop stops emitting after the first miss (the loop
returns exit 3 on the first failure without processing further
files). Matches the "fail-closed on audit" I4/D3 discipline.

## paideia-as conformance

- Module basename `AuditStub` (PascalCase); no directory prefix.
- No `test` mnemonic; every zero-check via `cmp reg, 0`.
- All `cmp reg, imm` immediates ≤ 0x7FFFFFFF (max 1 for the
  broker-failed check).
- r11 scratch; reloaded before every `.bss` read/write.
- No byte reads in this module — all state is u64-wide.
- All functions are leaf (no `call` inside); no push/pop parity
  to preserve.
- `.bss` slot names prefixed `_audit_` to sidestep cross-repo
  unqualified-name collisions.

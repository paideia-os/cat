# cat — plans/

Per-milestone implementation notes.

- `m1-001-notes.md` — scaffold + caps.decl + skeleton dispatcher (LANDED).
- `m1-002-notes.md` — argv surface (flags + multi-positional) (LANDED).
- `m1-003-notes.md` — first-runnable single-file KIND_TTY output (LANDED).
- `m2-001-notes.md` — multi-file concatenation, arg-order preserved (LANDED).
- `m2-002-notes.md` — -n line numbering + -A non-printable rendering (LANDED).
- `m2-003-notes.md` — streaming reads with 64 KiB chunks (LANDED).
- `m2-004-notes.md` — stdin passthrough via KIND_IPC_ENDPOINT (LANDED).
- `m3-001-notes.md` — schema-typed passthrough via PipeOut +
  FileSchema (LANDED).
- `m3-002-notes.md` — RawByteChunk[] emission for schemaless
  files (LANDED).
- `m3-003-notes.md` — FileReadRecord audit-first gate via
  AuditStub (LANDED).

Upstream: `design/tooling/r49-r50-plan.md` §5.5 in the paideia-os
repo.

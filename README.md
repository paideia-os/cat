# cat

paideia-os file read/concatenate (schema-passthrough on semantic pipes).

## Status

**Released — v1.0.0.** M5 (dual-signed release + `.pdxdoc` +
mirror push) CLOSED. `cat` is released per the milestone rubric.
See `STATUS.md` for the per-issue rollup, `CHANGELOG.md` for the
v1.0.0 entry, `MIRROR.md` for the staging-push payload, and
`design/tooling/r49-r50-plan.md` §5.5 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo for
the full milestone breakdown (M1–M5), KIND allocations, and
cross-repo dependencies.

Physical push to `pkgs.paideia-os` is deferred to T-INFRA-001 +
T-INFRA-002 in the paideia-os meta repo (see `MIRROR.md` §1).
`manifest.pdxsig` §6/§7 signature bytes are `PENDING` pending
`paideia-as v0.33-crypto` (ML-DSA-65 primitive) + the signing bot
host.

## Layout

```
caps.decl                            # required capabilities (invariant I6)
deps.list                            # shared-lib deps (empty at v1.0)
manifest.pdxsig                      # dual-signed pkg manifest (§D4)
cat.pdxdoc                           # long-form doc, `doc cat` back-end (I7 §2)
CHANGELOG.md                         # release history
MIRROR.md                            # pkgs.paideia-os staging push manifest
design/architecture.md               # internal shape spec
src/argv_dispatch.pdx                # CatDispatch: argv scan + top-level dispatcher
src/file_read.pdx                    # FileRead: streaming open/read-chunk/close
src/stdin_source.pdx                 # StdinSource: streaming stdin read
src/render.pdx                       # Render: -n / -A transformations
src/tty_sink.pdx                     # TtySink: bounded write sink (M1) → KIND_TTY (shell.M4)
src/pipe_out.pdx                     # PipeOut: semantic-pipe frame emitter (M3-001)
src/file_schema.pdx                  # FileSchema: per-handle schema-hash lookup (M3-001)
src/raw_byte_chunk.pdx               # RawByteChunk: schemaless-file record emission (M3-002)
src/audit_stub.pdx                   # AuditStub: per-file FileReadRecord gate (M3-003)
STATUS.md                            # milestone + issue rollup
tests/README.md                      # test matrix summary
tests/m4_001_multi_file_order.pdx    # M4-001: argv-order preservation
tests/m4_002_schema_passthrough.pdx  # M4-002: R20b frame + hash + body passthrough
tests/m4_003_large_file_streaming.pdx# M4-003: bounded working-set streaming
tests/m4_004_stdin_pipe.pdx          # M4-004: stdin passthrough (audit NOT fired)
```

## Compliance

Every source and test file observes paideia-as v0.33 conformance:
Module-basename-pascal + no-test-mnemonic + cmp-imm32-only +
r11-scratch + byte-load-zero-then-mov_b + sysv-push-pop-parity, per
`design/architecture.md` §5.

## License

MIT — see LICENSE.

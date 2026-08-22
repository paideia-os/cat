# cat

paideia-os file read/concatenate (schema-passthrough on semantic pipes).

## Status

M3 (schema-typed passthrough + RawByteChunk[] emission for
schemaless files + FileReadRecord audit-first gate) CLOSED —
audit-conformant per the milestone rubric. See `STATUS.md` for
the per-issue rollup and `design/tooling/r49-r50-plan.md` §5.5
in the [paideia-os](https://github.com/paideia-os/paideia-os)
repo for the full milestone breakdown (M1–M5), KIND allocations,
and cross-repo dependencies.

## Layout

```
caps.decl                    # required capabilities (invariant I6)
design/architecture.md       # internal shape spec
src/argv_dispatch.pdx        # CatDispatch: argv scan + top-level dispatcher
src/file_read.pdx            # FileRead: streaming open/read-chunk/close
src/stdin_source.pdx         # StdinSource: streaming stdin read
src/render.pdx               # Render: -n / -A transformations
src/tty_sink.pdx             # TtySink: bounded write sink (M1) → KIND_TTY (shell.M4)
src/pipe_out.pdx             # PipeOut: semantic-pipe frame emitter (M3-001)
src/file_schema.pdx          # FileSchema: per-handle schema-hash lookup (M3-001)
src/raw_byte_chunk.pdx       # RawByteChunk: schemaless-file record emission (M3-002)
src/audit_stub.pdx           # AuditStub: per-file FileReadRecord gate (M3-003)
STATUS.md                    # milestone + issue rollup
tests/README.md              # placeholder — correctness matrix lands at M4
```

## Compliance

Every source file observes paideia-as v0.33 conformance:
Module-basename-pascal + no-test-mnemonic + cmp-imm32-only +
r11-scratch + byte-load-zero-then-mov_b + sysv-push-pop-parity, per
`design/architecture.md` §5.

## License

MIT — see LICENSE.

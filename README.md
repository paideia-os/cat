# cat

paideia-os file read/concatenate (schema-passthrough on semantic pipes).

## Status

M1 (design + skeleton) in progress. See `STATUS.md` for the per-issue
rollup and `design/tooling/r49-r50-plan.md` §5.5 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo for the
full milestone breakdown (M1–M5), KIND allocations, and cross-repo
dependencies.

## Layout

```
caps.decl                    # required capabilities (invariant I6)
design/architecture.md       # internal shape spec (M1 scope)
src/argv_dispatch.pdx        # CatDispatch: argv scan + top-level dispatcher
src/file_read.pdx            # FileRead: file-read stub (M1) → real syscall (M2)
src/tty_sink.pdx             # TtySink: bounded write sink (M1) → KIND_TTY (M2)
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

# tests/

Empty at M1 by design. The correctness matrix — multi-file
order-preservation + schema-typed passthrough against a known-schema
fixture + large-file streaming (no OOM on files > RAM) + stdin
piping through a shell pipeline — lands with `cat.M4-001` through
`cat.M4-004` per `design/tooling/r49-r50-plan.md` §5.5 in
paideia-os.

The M1 first-runnable example (a caller passes a hardcoded byte
buffer through `CatDispatch::cat_dispatch_from_buf` and observes
the sink output) is carried by the first consumer that wires cat's
TtySink to KIND_TTY — either the shell's exec path or the M2
file-read pipeline. M1 has no automated test in this tree.

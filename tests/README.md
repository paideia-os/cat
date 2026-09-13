# tests/

M4 correctness matrix per `design/tooling/r49-r50-plan.md` §5.5
in paideia-os. Every test module is a `.pdx` file compiled with
the same paideia-as toolchain as the `src/` tree; each carries a
single public entry function that returns 0 on PASS and a
distinct non-zero exit code per assertion failure (so a driver
harness can decode without inspecting logs).

Every test uses the harness pattern documented at
`design/architecture.md` §3.2:

1. Populate fixture `.bss` slots (paideia-as has no data literals;
   every byte / pointer is written at test entry).
2. Reset the four stub tables `FileRead` / `StdinSource` /
   `AuditStub` / `FileSchema` — `cat_dispatch` does not reset
   these.
3. Seed the fixtures (`file_read_seed_push`, `stdin_seed`,
   `file_schema_seed`, `audit_stub_seed_broker_failure` if
   exercising the D3 refuse-output path).
4. Call `cat_dispatch(&argv, argc)`.
5. Assert on `TtySink::tty_out_buf` / `tty_out_len` / audit-count
   / (M4-002) frame header layout.

When the real substrates wire in (R42 PdxFS, shell.M2 pipeline,
shell.M4 tty handoff, libpdx-audit binding, libpdx-semantic-pipe
binding), the seed helpers are removed and the test-side setup
shrinks; the sink/audit assertions remain valid because those are
the correctness invariants, not the plumbing.

## Test matrix

| File                                | Issue | Focus                                    | Fail codes    |
|-------------------------------------|-------|------------------------------------------|---------------|
| `m4_001_multi_file_order.pdx`       | #11   | multi-file argv-order preservation       | 1..4          |
| `m4_002_schema_passthrough.pdx`     | #12   | schema-typed passthrough (R20b frame)    | 1..6          |
| `m4_003_large_file_streaming.pdx`   | #13   | streaming loop + bounded working set     | 1..4          |
| `m4_004_stdin_pipe.pdx`             | #14   | stdin path + audit-NOT-fired invariant   | 1..4          |
| `cat_errno_map.pdx` + `errno_capture.pdx` | #31 | errno-to-diagnostic mapping (7 rows, replicates `entry.pdx`'s dispatch) | 1..7 |
| `qemu_e2e_cat_smoke.sh`             | #32   | end-to-end serial-log fingerprint (v1.1-A substrate) | 0/1/77 |

Note: `qemu_e2e_cat_smoke.sh` is a bash driver script, not a `.pdx`
module. It exits 0 on PASS, 1 on FAIL (fingerprint bytes absent),
and 77 on SKIP (bin_seeds satellite cutover / monorepo checkout
preconditions unmet — see the script header for the four skip
gates). It is deliberately outside the M4 correctness matrix
because it exercises the whole boot → shell → exec → syscall chain
rather than the module contracts in isolation.

Fail-code codebook per file is the header comment at the top of
that file.

## Test entry points

Each module publishes exactly one test entry:

```
CatM4001 :: test_cat_m4_001_multi_file_order  : () -> u64
CatM4002 :: test_cat_m4_002_schema_passthrough : () -> u64
CatM4003 :: test_cat_m4_003_large_file_streaming : () -> u64
CatM4004 :: test_cat_m4_004_stdin_pipe : () -> u64
CatErrnoMap :: test_cat_errno_map_all : () -> u64
```

A shell.M4 driver harness (post-shell.M4 landing) will invoke
each in sequence, collect the four exit codes, and report the
matrix as `PASS` iff all four are 0.

## M1 first-runnable note

The M1 first-runnable example (`cat_dispatch_from_buf(buf, len)`
driving `TtySink::tty_write_bytes` directly) is not carried by
the M4 matrix — that alt entry stays as a smoke-check for the
sink cap and is exercised by whoever wires cat's TtySink to
KIND_TTY (the shell's exec path).

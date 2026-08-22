# cat.M1-001 — implementation notes

**Issue:** #1 — scaffold + caps.decl (one KIND_PDXFS_FILE cap per
file arg)
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.5 (paideia-os).

## What landed

- `caps.decl` — four required caps
  (`KIND_USER` + `KIND_TTY(write)` + `KIND_PDXFS_FILE(read,
  <arg-path>)` + `KIND_IPC_ENDPOINT`); one declared output schema
  (`RawByteChunk@0.1`, wire binding at M3-002). The per-argument
  narrowing of `KIND_PDXFS_FILE(read, <arg-path>)` is documented
  inline so the shell's `cap_pack(slot, narrow_rights)` at
  libpdx-cap M2 knows to mint one cap per positional file
  argument.
- `design/architecture.md` — full M1 spec covering all three M1
  issues (§2 pre-describes the argv grammar that #2 implements;
  §3 pre-describes the dispatch pipeline that #3 wires end-to-end;
  §6 lists the cross-repo dependencies + substrate blockers).
  Includes the exit-code discipline, storage model, paideia-as
  conformance, and explicit M1 non-goals.
- `src/argv_dispatch.pdx` — `CatDispatch` module:
  - Exit-code constants: `CAT_EXIT_OK`, `CAT_EXIT_USAGE_ERROR`,
    `CAT_EXIT_SYSTEM_ERROR`, `CAT_EXIT_CAP_DENIED`.
  - Argv-scan constant: `NAME_MAX_LEN = 236` (matches doc
    reader's shared upper bound).
  - `.bss` singleton: `first_positional_ptr`,
    `first_positional_len` (M1-002 supersedes these with
    `pos_ptrs` + `pos_count`).
  - `cat_dispatch(argv, argc)` — argv scan → name-len measure →
    inline `file_read_stub` → `CAT_EXIT_CAP_DENIED`. Non-leaf; 3-
    push callee-save + alignment prologue.
  - `file_read_stub()` — inline M1-001 stub returning 0
    unconditionally; M1-003 removes this definition and re-hosts
    the symbol in `src/file_read.pdx` (symbol-swap edit; call
    site in `cat_dispatch` is unchanged).
- `README.md` — expanded layout + compliance pointer.
- `STATUS.md` — M1-001 LANDED, M1-002 + M1-003 pending.
- `tests/README.md` — placeholder for M4 correctness matrix.

## Design decisions

**Signature freeze at M1-001.** `cat_dispatch(argv, argc) →
exit_code` is the interface every downstream caller pins against.
M1-002 replaces the inline single-positional argv scan with a
proper `cat_parse_argv` (flag mask + multi-positional list) but
`cat_dispatch`'s external shape does not change. M1-003 wires the
TtySink at the file-read-tail and adds the alt entry
`cat_dispatch_from_buf(buf, buf_len)`. Both later edits are body-
only or additive.

**Inline argv scan at M1 (not libpdx-argv).** cat's -n and -A are
boolean flags. libpdx-argv M1-002's short-flag parser consumes
`argv[i+1]` as a value if it does not start with `-`; under that
semantics `cat -n foo.txt` binds `foo.txt` to `-n` and leaves
`pos_count == 0`. The migration to libpdx-argv is deferred to
cat.M2 once libpdx-argv M2's declarative "these flags are
boolean" API lands. Documented in `design/architecture.md` §2.

**file_read_stub inlined in argv_dispatch.pdx at M1-001, moved to
file_read.pdx at M1-003.** The inline stub lets the M1-001
scaffold compile standalone before src/file_read.pdx exists. The
M1-003 move is a pure symbol relocation — the call site in
`cat_dispatch` sees the same symbol name; the linker resolves it
to the new location. This is the same shape libpdx-cap M1-001
used for `cap_manifest_verify`.

## paideia-as conformance

- Module `CatDispatch` (PascalCase basename, no directory prefix).
- No `test` mnemonic; every zero-check via `cmp reg, 0`.
- Every `cmp reg, imm` uses immediate ≤ 0x7FFFFFFF (max = 236 =
  `NAME_MAX_LEN`; the '-' compare uses 0x2D).
- `r11` scratch; reloaded before every `.bss` read/write.
- Byte loads use `xor rax, rax; mov_b rax, [ptr]` (#1248
  mitigation).
- SysV push/pop parity: `cat_dispatch` pushes `r12/r13/r14`
  (3-push prologue → rsp%16 == 0 at every nested call site);
  epilogue pops in mirror order.

# cat.M1-002 — implementation notes

**Issue:** #2 — argv surface via libpdx-argv (cat [-n|-A|--schema]
<file>...)
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.5 (paideia-os).

## What landed

- `src/argv_dispatch.pdx` — extended `CatDispatch` with a proper
  argv parser:
  - New constants: `PARSE_OK`, `PARSE_ERR_UNKNOWN_LONG_FLAG`,
    `PARSE_ERR_UNKNOWN_OR_CLUSTERED_SHORT`,
    `PARSE_ERR_POS_OVERFLOW`, `PARSE_ERR_LONG_MISSING_NAME`,
    `PARSE_ERR_NAME_TOO_LONG` (internal to `cat_parse_argv`;
    collapsed by `cat_dispatch` into `CAT_EXIT_USAGE_ERROR`).
  - New constants: `FLAG_N = 0x1`, `FLAG_A = 0x2`,
    `FLAG_SCHEMA = 0x4` (bit-mask storage).
  - New constant: `POS_MAX = 8` (positional-file cap at M1; M2-003
    removes the cap).
  - New `.bss` slots: `flag_mask`, `pos_ptrs[8]`, `pos_count`,
    `parse_error_arg_index`. The M1-001 slots
    `first_positional_ptr` + `first_positional_len` are removed;
    `pos_ptrs[0]` + a walk-to-NUL is the M1-002 equivalent.
  - New function `cat_reset()` — zero parse state (leaf).
  - New function `cat_parse_argv(argv, argc) → rc` — the parser
    (leaf; classifies each arg into long-flag / short-flag /
    positional / bare "-").
  - Updated `cat_dispatch(argv, argc)` — now runs `cat_reset` →
    `cat_parse_argv` → `pos_count == 0` check → `file_read_stub`.
    Non-leaf; 3-push callee-save + alignment prologue preserved.
- `STATUS.md` — M1-002 LANDED.

## Grammar decisions

**Long-flag whitelist at M1: only `--schema`.** Byte-exact compare
against `s`, `c`, `h`, `e`, `m`, `a` + NUL (mirrors libpdx-argv's
own `--pdx-schema` inline compare in `src/parser.pdx`). Any other
long-flag name is `PARSE_ERR_UNKNOWN_LONG_FLAG`. Bare `--` or
`--=foo` is `PARSE_ERR_LONG_MISSING_NAME`. Long flags with `=value`
(e.g. `--schema=1`) are also `PARSE_ERR_UNKNOWN_LONG_FLAG` at M1
because `--schema` is boolean-only — a `=value` sequence would
force byte-8 to be `=` (0x3D) instead of NUL and the byte-exact
compare rejects it.

**Short-flag whitelist at M1: `-n`, `-A`.** Exactly one letter
after `-` + NUL (byte 2 must be NUL, else `PARSE_ERR_UNKNOWN_OR_
CLUSTERED_SHORT` per the D3 one-per-hyphen contract from
`design/tooling/plan.md` §3.4). Case-sensitive (`-N` is not `-n`).
Letter dispatch is a two-way `cmp rax, 0x6E` / `cmp rax, 0x41`
switch; the M2 short-flag vocabulary expansion will extend this
list (`-b` = number non-blank lines, `-E` = show line ends, `-T`
= show tabs — see coreutils muscle memory in `design/tooling/
plan.md` §5).

**Bare `-` is a positional.** POSIX-standard "stdin here" marker.
At M1 it is collected into `pos_ptrs` like any other positional
argument; M2-004's stdin-passthrough work will handle the
"pos_ptrs[i] points at `\"-\"`" case by reading from
KIND_IPC_ENDPOINT instead of KIND_PDXFS_FILE for that slot.

**Positional length bound: `NAME_MAX_LEN = 236`.** Shared with the
doc reader (see doc.M1-001). Longer paths return
`PARSE_ERR_NAME_TOO_LONG`. The true KIND_PDXFS_FILE path bound at
R42 substrate is 4 KiB; the M1 conservatism keeps the hand-audit
surface small across R49/R50 tools.

**Positional count bound: `POS_MAX = 8`.** M1 ceiling. M2-003's
streaming-read work removes the cap; the parser will migrate to
libpdx-argv M2 at the same time. Exceeding 8 returns
`PARSE_ERR_POS_OVERFLOW`.

**Empty argv entry (argv[i] == "\0") is `PARSE_ERR_POS_OVERFLOW`.**
Collapsed to the same code so the M4 diagnostic renderer prints
one uniform "positional slot" message. A truly separate
"empty-positional" error code adds surface without adding
observability at M1.

## Why not libpdx-argv at M1

libpdx-argv M1-002's short-flag parser consumes `argv[i+1]` as a
value if it does not start with `-`. Under that semantics `cat -n
foo.txt` binds `foo.txt` to `-n` and leaves `pos_count == 0`,
which is a user-facing bug (cat reads no file). Migration to
libpdx-argv waits for libpdx-argv M2's declarative "these flags
are boolean (arity 0)" API. The inline parser here produces the
same `pos_ptrs` shape + `flag_mask` bit layout that libpdx-argv M2
will produce, so the M2 migration is a call-site swap (replace
`cat_reset` + `cat_parse_argv` with `ParsedArgs::reset` +
`Parser::parse_argv` + a bit-mask synthesis pass) — not a
data-shape rewrite. Documented in `design/architecture.md` §2.

## paideia-as conformance

- Every `cmp reg, imm` uses immediate ≤ 0x7FFFFFFF (largest at
  M1-002: 236 for `NAME_MAX_LEN`, 8 for `POS_MAX`; per-byte ASCII
  compares fit trivially).
- `r11` is used as scratch for `.bss` `lea` addressing AND as the
  length accumulator inside the positional-measure loop (it is
  never live across a `.bss` access in that scope; every reload
  happens at loop exit before the next `.bss` op).
- Every byte read preceded by `xor rax, rax; mov_b rax, [ptr]`
  (#1248 mitigation).
- Instruction set stays inside the R49 subset. `or rax, imm` is
  used for the flag-bit-mask update; no `sub`/`neg`/`not`/`inc`/
  `dec` on general regs.
- SysV push/pop parity: `cat_parse_argv`, `cat_reset`, and
  `file_read_stub` are all leaf (no `call` inside). `cat_dispatch`
  is non-leaf with a 3-push callee-save + alignment prologue.

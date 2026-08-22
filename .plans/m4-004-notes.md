# cat.M4-004 — implementation notes

**Issue:** #14 — stdin-piping test (`a | cat | b` through a shell
pipeline)
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.5 (paideia-os).

## What landed

- `tests/m4_004_stdin_pipe.pdx` — new `CatM4004` module:
  - Fixture `.bss`: 6-byte stdin source (`"PIPED\n"`), matching
    6-byte expected sink buffer, `"cat\0"` name string, and the
    1-slot argv pointer array.
  - `test_cat_m4_004_stdin_pipe()` — non-leaf entry with a
    5-push callee-save prologue. Populates fixtures at runtime,
    resets stub tables, seeds `StdinSource` via `stdin_seed`,
    calls `cat_dispatch(&argv, 1)`, and asserts: exit=0,
    `tty_out_len`=6, audit count=0 (stdin path has NO
    audit), sink bytes 0..6 byte-equal to `"PIPED\n"`.

## Design decisions

**`argc = 1` routes to stdin.** `cat_dispatch`'s branch at
`src/argv_dispatch.pdx:408` — `cmp r13, 0; je cd_stdin_path` —
tests `pos_count`. With only `argv[0]` supplied, `cat_parse_argv`
records zero positionals; the stdin arm takes over. This mirrors
the real shell pipeline `a | cat | b` where `cat` receives no
file arguments and its stdin/stdout endpoints are bound by the
shell.

**Audit count MUST be 0 on the stdin path.** The M3-003
audit-first call is inside the per-file loop (positional path
only). The stdin path has no file to record — a future
`StdinReadRecord` / `IPCReceiveRecord` is a shell.M3 concern per
the file-header note at `src/argv_dispatch.pdx:59`. This
assertion is load-bearing: a bug that moved the audit call to
the top of dispatch would fail here with `_audit_file_count == 1`.

**Render fast-path passthrough is observed via byte equality.**
With `flags == 0` (neither `-n` nor `-A`),
`Render::render_write_bytes` takes the fast-path (single
`tty_write_bytes(rdi, rsi)` call at `src/render.pdx:642`). The
sink content therefore byte-equals the stdin source
byte-for-byte — no line-number prefixing, no non-printable
escapes. Assertion 4 (byte-scan) catches any drift.

## paideia-as conformance

- Module basename `CatM4004` (PascalCase); no directory prefix.
- No `test` mnemonic; every zero-check via `cmp reg, 0`.
- All `cmp reg, imm` immediates ≤ 0x7FFFFFFF (max 6).
- r11 scratch; reloaded before every `.bss` read/write.
- Byte reads use `xor rax, rax; mov_b rax, [ptr]` (#1248).
- 5-push callee-save prologue (rbx = sink base, r12 = expected
  base, r13 = scan cursor, r14 = expected byte, r15 = pad) lands
  rsp%16 == 0 at every nested call site.
- `.bss` slot names prefixed `m4_004_` to sidestep cross-repo
  unqualified-name collisions.

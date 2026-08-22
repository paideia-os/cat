# cat.M2-004 — implementation notes

**Issue:** #7 — stdin passthrough when argv empty (read from
KIND_IPC_ENDPOINT)
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.5 (paideia-os).

## What landed

- `src/stdin_source.pdx` — new `StdinSource` module:
  - Single-source triple `sr_stdin_buf` / `sr_stdin_len` /
    `sr_stdin_cursor` (M2-stub state; deleted at shell.M2
    landing).
  - `stdin_reset()` — zeroes the three slots.
  - `stdin_seed(buf, len)` — M4 test harness helper: sets the
    source pointer + length. Cursor stays zero from the paired
    `stdin_reset` call.
  - `stdin_read_chunk(dst, cap)` — streams up to min(cap,
    CHUNK_MAX, remaining) bytes into the caller-owned
    destination, advances the cursor, returns bytes copied
    (0 = EOF or no seed pushed).
- `src/argv_dispatch.pdx` — `cat_dispatch`'s pos_count == 0
  branch takes the stdin path: loop `stdin_read_chunk(fr_chunk_
  buf, CHUNK_MAX)` → `render_write_bytes(fr_chunk_buf, bytes)`
  until EOF. The stdin path replaces the M1 arm that returned
  CAT_EXIT_USAGE_ERROR (2) for zero positionals.

## Design decisions

**Shape parity with `FileRead::file_read_chunk`.** The stdin
read function returns bytes copied (0 = EOF) with the same
CHUNK_MAX cap; `cat_dispatch` uses the same per-chunk loop shape
as the file path. The only branch is at the top of dispatch
(`cmp r13, 0; je cd_stdin_path`).

**No CAT_EXIT_CAP_DENIED on the stdin path.** A live stdin never
"opens" — there's no equivalent to `file_open` returning 0. The
stub returns 0 on the first read when no seed is pushed, which
`cat_dispatch` treats identically to end-of-input on a real
stdin. So `cat` with no argv reading from an empty stdin cleanly
exits 0 with zero output — matching POSIX cat semantics.

**Stub interface matches R20b sys_ipc_recv shape.** The shell.M2
landing (r49-r50-plan.md §5.2 shell.M2) will replace the stub
body with a `sys_ipc_recv` wrapper via libpdx-cap. The function
signature (`(dst, cap) -> bytes`) is what the real wrapper
exposes: cat_dispatch's call site is unchanged.

**Seed pointer NULL check.** `stdin_read_chunk` checks
`sr_stdin_buf == 0` before reading; NULL means no seed was ever
pushed and the function returns 0 (EOF). This mirrors what a
real disconnected KIND_IPC_ENDPOINT will return once shell.M2
lands (an unconnected endpoint's recv returns 0 bytes).

## paideia-as conformance

- Symbols prefixed with `sr_` (stdin-source) — sidesteps
  cross-repo unqualified-name collisions.
- `stdin_read_chunk` uses the same three cmp+jge guard pattern
  from `file_read_chunk` (no `sub reg, reg`; no negative
  `add reg, imm`).
- All three functions are strict leaves; no push/pop parity.
- Every `cmp reg, imm` uses immediate ≤ 0x7FFFFFFF (largest:
  65536 for CHUNK_MAX).
- Byte reads use `xor rax, rax; mov_b rax, [r11]` (#1248).
- Byte writes to the caller-owned destination use `lea r11,
  [rdi + rcx*1]; mov_b [r11], rax`.

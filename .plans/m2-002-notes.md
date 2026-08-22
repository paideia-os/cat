# cat.M2-002 — implementation notes

**Issue:** #5 — -n line-numbering + -A non-printable rendering
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.5 (paideia-os).

## What landed

- `src/render.pdx` — new `Render` module implementing the -n
  and -A transformation layer.
  - `render_reset(flags)` — leaf; initialises the counter to 1
    and marks at-line-start. Called ONCE per cat invocation
    (before the file loop) so line numbering is CONTINUOUS
    across concatenated files, matching GNU cat -n semantics.
  - `render_write_bytes(src, len)` — non-leaf; the main M2 byte
    pump. Fast-path when flags == 0 (single
    `tty_write_bytes(rdi, rsi)` call); slow-path per-byte
    dispatch through prefix / newline / -A byte / raw-emit
    branches.
  - `render_emit_line_num_prefix()` — non-leaf; emits the
    right-justified 6-column line number followed by a tab, then
    increments the counter. 6-place unrolled digit extraction
    (10^5, 10^4, ..., 10^0). Leading zeros before the first
    non-zero digit emit as spaces; subsequent zeros emit as
    `0`. Numbers ≥ 1000000 print without padding (leading-
    space region collapses to zero). u64 values > 999999 through
    the 6-place unroll drop leading digits — M2 trade-off
    accepted because files > 1M lines are pathological; softarch
    R42 pass will extend to a 20-place unroll once
    KIND_PDXFS_FILE lets us exercise real files.
  - `render_emit_A_byte(byte)` — non-leaf; applies the -A
    escape rules to a single non-newline byte. High bytes
    (>= 0x80) emit `M-` and re-dispatch on `byte & 0x7F`
    inlined via label jump (masked byte is guaranteed < 0x80 so
    no true recursion).
- `src/tty_sink.pdx` — added `tty_write_byte(byte)` leaf helper
  for the Render layer's per-byte emission (line-num digits,
  escape prefixes). Bumped `TTY_OUT_CAP` from 4 KiB (M1) to
  64 KiB (M2) so the streaming path + render inflation can be
  exercised end-to-end from the M4 harness without exhausting
  the sink on the first chunk.
- `src/argv_dispatch.pdx` — `cat_dispatch` calls `render_reset
  (flag_mask)` after `tty_reset` and before the file / stdin
  loop; the loops call `render_write_bytes(fr_chunk_buf,
  bytes)` per chunk (in place of the M1 `tty_write_bytes`
  direct call).

## Design decisions

**Line numbering is continuous across concatenated files.**
`render_reset` is called ONCE per `cat_dispatch` invocation, not
per file. This matches GNU cat -n behaviour on `cat -n a b` —
lines are numbered continuously through both files (never
restarted per file). If the M4 fixture set demands per-file
restart, softarch's Round 3 refinement will add an alt entry
`render_reset_line_num_only()` called between file iterations.

**6-place digit unroll instead of a general u64 → decimal
routine.** A general u64 decimal render needs either div/mul (not
in the R49 subset) or a 20-place unroll with imm64 constants
(only 4 of the 20 places have their `add rax, -pow10` fitting in
imm32). The 6-place limit keeps every immediate ≤ 0x7FFFFFFF and
covers every realistic line-numbering case. Numbers > 999999
still print (leading spaces collapse to zero) but drop leading
digits above the 6-place window — a documented M2 trade-off.

**Fast path when flags == 0.** `cat file` with no flags is the
overwhelmingly common invocation. `render_write_bytes` checks
`render_flags == 0` first and, if so, single-call passes through
to `tty_write_bytes(rdi, rsi)` — no per-byte overhead. The
per-byte slow path activates only when -n or -A is set.

**`add reg, -N` for digit extraction.** paideia-as encodes
`add reg64, imm8/imm32` with a signed immediate (see encoder
tests `add_reg64_imm8_negative_value` +
`add_reg64_imm32_fitting_value`); the M2 render layer uses this
to count digit hits at each 10^k place. The `sub` mnemonic is
still avoided so the M1 style ban carries forward — the
`add reg, -N` form is a natural x86 encoding that keeps the
vocabulary tight.

## paideia-as conformance

- All three non-leaf Render functions use 5-push callee-save
  prologues (rbx / r12 / r13 / r14 / r15) so rsp%16 == 0 at
  every nested `tty_write_byte` / `render_emit_line_num_prefix`
  / `render_emit_A_byte` call site.
- Byte reads in `render_write_bytes` use `xor rax, rax; mov_b
  rax, [rbx]` (#1248). Byte writes go through
  `tty_write_byte(rdi)` — the sink helper handles the
  `mov_b [ptr], rdi` internally.
- Every `cmp reg, imm` uses immediate ≤ 0x7FFFFFFF (largest:
  100000 for the 10^5 digit-place).
- Line-number prefix bytes (digits + tab) go DIRECTLY to
  `tty_write_byte` — the prefix's tab is never rendered as
  `^I` even under -A. Matches GNU cat -An.
- `render_emit_A_byte`'s high-byte 'M-' + re-dispatch is
  inlined via `jmp eab_dispatch` from `and rbx, 0x7F` — the
  masked byte is guaranteed < 0x80 so at most two label
  iterations execute.

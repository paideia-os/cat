# cat.M1-003 — implementation notes

**Issue:** #3 — first runnable: single-file KIND_TTY output
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.5 (paideia-os).

## What landed

- `src/file_read.pdx` — new `FileRead` module:
  - `.bss`: `file_src_len : u64` (companion byte-count to
    `file_read_stub`'s rax return; 0 at M1).
  - `file_read_stub()` — leaf function returning 0 unconditionally
    (file not found) and writing 0 into `file_src_len`. M2 replaces
    the body with a `KIND_PDXFS_FILE(read)` syscall wrapper via
    libpdx-cap; the `(rax, file_src_len)` return contract is
    preserved so the M2 edit is body-only inside this file.
  - This is the M1-003 re-host of the symbol previously inlined in
    `src/argv_dispatch.pdx` at M1-001 / M1-002. The call site in
    `cat_dispatch` is unchanged; the linker resolves the bare
    `file_read_stub` name to the new location.
- `src/tty_sink.pdx` — new `TtySink` module:
  - Return codes: `TTY_OK = 0`, `TTY_SINK_OVERFLOW = 0xFFFFFFF4`.
  - Sink capacity: `TTY_OUT_CAP = 4096`.
  - `.bss`: `tty_out_buf : [u8; 4096]`, `tty_out_len : u64`
    (bytes-written cursor).
  - `tty_reset()` — leaf; zeroes `tty_out_len`. Buffer past
    cursor is unreachable so no wipe is needed.
  - `tty_write_bytes(buf, len)` — leaf; per-byte copy from
    `[buf, buf+len)` into `tty_out_buf` starting at
    `tty_out_len`. Overflow leaves `tty_out_len` at the
    partial-write cursor and returns `TTY_SINK_OVERFLOW` (mirrors
    KIND_TTY(write)'s partial-write shape so the caller's error
    handling does not change across the M1→M2 migration).
- `src/argv_dispatch.pdx` — extended `CatDispatch`:
  - Removed the inline `file_read_stub` definition (re-hosted to
    `src/file_read.pdx`). The call site is unchanged; the linker
    resolves the bare symbol to the new location.
  - Extended `cat_dispatch` (step 5): after `file_read_stub`
    returns a non-zero src ptr, stash the ptr in r12 (argv is no
    longer needed at this point), call `tty_reset`, then call
    `tty_write_bytes(src_ptr, file_src_len)`. Sink overflow →
    `CAT_EXIT_SYSTEM_ERROR`. The unreachable-at-M1 fall-through
    arm is now the M2 correctness path.
  - Added `cat_dispatch_from_buf(buf, buf_len)` alt entry — the
    earliest end-to-end runnable in the tree. Skips argv + file
    read; drives `tty_reset` + `tty_write_bytes` directly. Used
    by M4 tests + the M1 smoke fixture. Non-leaf; 3-push callee-
    save + alignment prologue same as `cat_dispatch`.
- `STATUS.md` — M1-003 LANDED, M1 CLOSED. Ready-for-M2 pointer
  added.
- `.plans/README.md` — M1-003 flagged LANDED.

## Design decisions

**Bounded sink stands in for KIND_TTY(write).** The M1 sink is a
4 KiB `.bss` scratch buffer; a body larger than 4 KiB returns
`TTY_SINK_OVERFLOW`, which `cat_dispatch` collapses to
`CAT_EXIT_SYSTEM_ERROR` (3). That is exactly the code M2's
KIND_TTY(write) partial-write returns for an I/O failure, so the
caller's error handling code stays fixed across the migration.
The sink field names (`tty_out_buf`, `tty_out_len`) do not change
between M1 and M2 either — the M2 patch is a leaf-function body
edit inside `tty_write_bytes`.

**r12 doubles as argv-carry then src-ptr-stash inside cat_dispatch.**
After `cat_parse_argv` returns, `cat_dispatch` never reads argv or
argc again (the parser owns their transfer to `pos_ptrs` + flag
bits). r12 becomes free to hold the file-read src ptr across the
`tty_reset` call. This avoids adding a fourth push to the
prologue and keeps the 3-push alignment idiom unchanged.

**Alt entry cat_dispatch_from_buf skips both blockers.** R42
substrate (KIND_PDXFS_FILE) is not in the kernel at HEAD
(2026-08-21); shell.M4's KIND_TTY handoff is not landed either.
The alt entry lets a test fixture drive the M1 sink pipeline
without either blocker — it is the earliest end-to-end runnable
piece of cat and mirrors the shape doc.M1-003 chose with its
`doc_dispatch_from_buf`.

## paideia-as conformance

- All three modules (`CatDispatch`, `FileRead`, `TtySink`) use
  PascalCase basenames without directory prefixes.
- Every `cmp reg, imm` uses immediate ≤ 0x7FFFFFFF (largest:
  4096 = `TTY_OUT_CAP`).
- r11 scratch, reloaded before every `.bss` access.
- Byte reads use `xor rax, rax; mov_b rax, [ptr]` (#1248 mitigation).
- Byte writes use `lea r10, [rip + tty_out_buf]; add r10, rcx;
  mov_b [r10], rax` — avoids `[base + reg]` byte-scale addressing
  (same idiom as doc's `DocRenderer::render_section`).
- SysV push/pop parity: `cat_dispatch_from_buf` uses the 3-push
  prologue (r12 = buf, r13 = buf_len, r14 = alignment pad). All
  leaf functions (`cat_reset`, `cat_parse_argv`, `file_read_stub`,
  `tty_reset`, `tty_write_bytes`) touch no callee-save regs.
- `TTY_SINK_OVERFLOW = 0xFFFFFFF4` is a 32-bit constant with the
  sign bit set; loaded via `mov rax, imm64` (no `cmp` uses this
  value, so the imm32 bound does not apply).

## Cross-module symbol resolution

`cat_dispatch` calls three symbols by unqualified linker name:
`file_read_stub` (`FileRead::file_read_stub` in
`src/file_read.pdx`), `tty_reset` and `tty_write_bytes` (both in
`TtySink` in `src/tty_sink.pdx`), plus `file_src_len` (`FileRead
::file_src_len` .bss slot). This is the same pattern doc's
`DocDispatch` uses when reading `PdxdocParser::section_count`,
libpdx-cap's `Cap` uses when reading `CapsDecl` symbols, and pkg's
`Dispatch` uses when calling `PkgList::pkg_list_body` — the R49
convention.

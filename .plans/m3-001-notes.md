# cat.M3-001 — implementation notes

**Issue:** #8 — schema-typed passthrough: if file declares schema,
forward records
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.5 (paideia-os).

## What landed

- `src/pipe_out.pdx` — new `PipeOut` module (semantic-pipe frame
  emitter stub):
  - `pipe_out_reset()` — leaf; no PipeOut-owned `.bss` state at
    M3 (all writes go through TtySink whose own reset zeroes the
    sink cursor). Kept as an API stub for symmetry with the
    future real libpdx-semantic-pipe binding-table reset.
  - `pipe_forward_frame(hash_ptr, body_ptr, body_len)` — emits
    ONE R20b IPC frame with schema-hash prefix into TtySink via
    `tty_write_byte` per byte. Header composed inline (op / ver /
    flags LE u16 / payload_len LE u32 = 32 + body_len). Body_len
    gated at SP_MAX_RECORD_BODY = 4056 (SP_MAX_PAYLOAD 4088 −
    SP_SCHEMA_HASH_SIZE 32).
  - `pipe_forward_write(hash_ptr, src_ptr, total_len)` —
    sub-chunks src into ≤ 4056-byte frames and calls
    `pipe_forward_frame` once per sub-chunk.
- `src/file_schema.pdx` — new `FileSchema` module (per-handle
  schema-hash lookup stub):
  - `file_schema_reset()` — zero all 9 slots of `_fs_hash_ptrs`.
  - `file_schema_seed(handle, hash_ptr)` — M4 test-harness helper
    associating a 32-byte schema-hash pointer with a specific
    file handle.
  - `file_schema_query(handle)` — returns the hash pointer for
    the given handle, or 0 for schemaless / out-of-range.
- `src/argv_dispatch.pdx` — `cat_dispatch` grows the FLAG_SCHEMA
  branch inside the per-file loop:
  - When FLAG_SCHEMA is set AND `file_schema_query(handle)`
    returns a non-zero hash_ptr, the per-chunk read now calls
    `pipe_forward_write(hash_ptr, fr_chunk_buf, bytes)` instead
    of `render_write_bytes`.
  - When FLAG_SCHEMA is clear, the M2 render path is preserved
    verbatim.

## Design decisions

**Frame wire format matches libpdx-semantic-pipe.** The 8-byte
header + 32-byte hash + body_len bytes layout mirrors the wire
format the real library will use — see the file-header comment in
`src/pipe_out.pdx` for the byte-by-byte layout. When
libpdx-semantic-pipe wires in (which needs a KIND_IPC_ENDPOINT
cap bound to a downstream consumer, a shell.M2 concern), the
frame emit path flips from `tty_write_byte` per byte to
`Send::send_frame` / `Passthrough::pipe_forward`; the dispatch
call site does not change.

**Per-chunk sub-framing.** File reads happen at CHUNK_MAX = 65536,
which exceeds the 4056-byte per-frame body cap. `pipe_forward_write`
handles the fan-out: sub-chunks the caller's total_len into ≤ 4056
byte frames and emits one `pipe_forward_frame` per sub-chunk. The
tail sub-chunk carries the residue (may be < 4056 bytes; skipped
if the write ends exactly on a 4056-byte boundary).

**No `sub` / no `add reg, -reg`.** paideia-as bans the `sub`
mnemonic and does not admit `add reg, -reg`. `pipe_forward_write`
tracks `bytes_left` as a countdown in r14, decrementing by the
fixed imm `add r14, -4056` on the full-chunk path only; the last
chunk path skips the decrement and terminates on `cmp r12, r13;
jge pfw_ok`. Signed imm32 form for `add reg, -imm` is documented
at `design/architecture.md` §5 (M2 addition for the Render digit
ladder).

**Schema-hash lookup is per-handle.** The R42 substrate will
expose a file's `.pdxfs` schema declaration via a
`sys_pdxfs_getxattr(handle, "pdxfs.schema", &out_hash, 32)`-shaped
syscall or an inline field on the KIND_PDXFS_FILE cap descriptor.
Neither exists at HEAD (2026-08-22). `FileSchema` ships a
test-seedable stub whose shape matches the eventual real lookup;
the M4 test harness seeds per-handle schema hashes via
`file_schema_seed(handle, hash_ptr)` before dispatch.

## paideia-as conformance

- Module basenames `PipeOut` / `FileSchema` (PascalCase); no
  directory prefix.
- No `test` mnemonic; every zero-check via `cmp reg, 0`.
- All `cmp reg, imm` immediates ≤ 0x7FFFFFFF (max 4056 for the
  body-len gate).
- r11 scratch; reloaded before every `.bss` read/write.
- Byte reads use `xor rax, rax; mov_b rax, [ptr]` (#1248).
- SysV push/pop parity: `pipe_forward_frame` and
  `pipe_forward_write` are non-leaf with 5-push callee-save
  prologues (rbx / r12 / r13 / r14 / r15) landing rsp%16 == 0 at
  every nested `tty_write_byte` / `pipe_forward_frame` call site.
- `.bss` slot names in `FileSchema` prefixed `_fs_` to sidestep
  cross-repo unqualified-name collisions (matches the R48
  vello↔vrr `vrc_→vrenc_` rename policy).

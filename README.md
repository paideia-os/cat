# cat

paideia-os file read/concatenate (schema-passthrough on semantic pipes).

## Synopsis

```
cat [-n] [-A] [--schema] <file>...      # read each file in argv order
cat [-n] [-A]                           # zero positionals: read stdin
```

Flags are boolean (arity 0) and may appear anywhere in `argv`. At most
`POS_MAX = 8` file arguments per invocation; each path is bounded at
`NAME_MAX_LEN = 255` bytes.

## Description

`cat` is a byte pump. It opens each positional file argument in the order
given, streams it in bounded chunks, and writes the bytes to the invoker's
terminal. With zero positional arguments it reads stdin instead — a
`KIND_IPC_ENDPOINT` frame stream minted by the invoking shell's pipeline.
Nothing is ever fully buffered: both source paths stage through a single
64 KiB `.bss` chunk buffer (`FileRead::fr_chunk_buf`, `CHUNK_MAX = 65536`),
so a 1 GiB file is streamed as 16384 chunks and the working set is constant
in file size.

Three output layers run off that stream. The **text layer** is the default:
bytes go verbatim to the sink, or through the `-n` line-numbering and `-A`
non-printable transforms when those flags are set. The **semantic-pipe
layer** is selected by `--schema`, and is a passthrough, not a re-encoding:
if a file's `.pdxfs` metadata declares a record schema, cat wraps the file's
own bytes in framed records carrying that schema's 32-byte hash, byte-exact;
if the file declares no schema, cat emits `RawByteChunk@0.1` records
(`offset` + `bytes`) so a downstream consumer can still window the stream by
byte range. The **audit layer** always runs on the file path: one
`FileReadRecord` is journaled per file argument *before* the first byte of
that file reaches the sink, and a journal failure aborts the read with exit
code 3 rather than emitting unjournaled output. The stdin path fires no
audit — there is no file to name — and takes no schema branch, since a pipe
carries no `.pdxfs` metadata.

Every function in the tree is declared `!{mem} @{}`: cat's own code claims
no capability effects, because at v1.0 the four substrates it would use
(`KIND_PDXFS_FILE` reads, `KIND_TTY` writes, `KIND_IPC_ENDPOINT` frames, the
audit broker) are in-tree, test-seedable stubs. The capability surface cat
is *granted* is the exec-time manifest in `caps.decl`, validated by the
shell before the process starts. See [Capabilities](#capabilities) and
[Substrate posture](#substrate-posture) below.

`cat` is a category-A coreutil of the R50 wave, and the first paideia-os
tool to reach v1.0 with a signed manifest and a `.pdxdoc`. Its
`cat.pdxdoc` section shape is the working reference for the other tool
repos' release milestones.

## Options

| Flag | Arg | Default | Description |
|------|-----|---------|-------------|
| `-n` | none | off | Prefix each output line with its line number, right-justified in a 6-column field, followed by a tab (`0x09`). Numbering starts at 1 and is **invocation-global** — it continues across concatenated files rather than restarting per file (`render_reset` runs once, before the file loop). Values above 999999 saturate to `999999` in the printed prefix; the internal counter keeps counting truthfully. |
| `-A` | none | off | Render non-printable bytes as visible escapes, matching GNU `cat -A` = `-vET`. See the table below. |
| `--schema` | none | off | Emit the semantic-pipe record layer for file arguments instead of rendered text. Per file: if the file declares a schema hash, forward its bytes as schema-typed records; otherwise emit `RawByteChunk@0.1` records. Ignored on the stdin path. |

`-A` byte mapping, as implemented in `Render::render_emit_A_byte` and
`Render::render_write_bytes`:

| Input byte | Output |
|------------|--------|
| `0x09` (TAB) | `^I` |
| `0x0A` (LF) | `$` then a real `\n` |
| `0x00`–`0x08`, `0x0B`–`0x1F` | `^` + (byte + `0x40`) — e.g. `0x01` → `^A` |
| `0x20`–`0x7E` | the byte, unchanged |
| `0x7F` (DEL) | `^?` |
| `0x80`–`0xFF` | `M-` then the rule above applied to (byte & `0x7F`) — e.g. `0x8A` → `M-^J` |

Behavioural notes traced to source:

- **`-n` and `-A` compose.** The line-number prefix bytes (padding, digits,
  tab) are written straight to the sink and are *not* run through the `-A`
  escaper, so `cat -An` never renders the prefix tab as `^I`.
- **`--schema` supersedes `-n` / `-A` for file arguments.** `cat_dispatch`
  branches on `FLAG_SCHEMA` before entering the render path, so under
  `--schema` the text transforms are not applied to file content.
- **No flags is a fast path.** When the flag mask is zero,
  `render_write_bytes` forwards the whole chunk in one `tty_write_bytes`
  call instead of dispatching per byte.
- **One letter per hyphen.** Clustered short flags (`-nA`) are rejected as a
  usage error; so is any unknown short flag, any long flag other than
  `--schema`, `--schema=value`, and a bare `--`.
- **A bare `-` is a positional**, not a flag (`argv[i][1] == 0` falls through
  to the positional path). `argv[0]` is always skipped.
- **`--version` is handled in `_start` (`src/entry.pdx`), not the argv
  parser.** As the sole argument (`argc == 2`, byte-exact `--version`) it
  prints the build version and exits 0 before `cat_reset`/`cat_parse_argv`
  ever run — ENH-005 (#20). Combined with anything else (`cat --version
  foo`) it falls through to the normal parser, whose long-flag whitelist in
  `src/argv_dispatch.pdx` still contains only `--schema`, so that
  combination exits 2 as an unrecognized long flag.
- **`--help` is not accepted, deliberately.** Long-form documentation is
  served by `doc cat` reading `cat.pdxdoc`, not a second copy of the flag
  table compiled into the binary.
- **`--schema` on a schemaless file does not fail.** `cat.pdxdoc` claims a
  refusal with exit 2 in that case; the implemented behaviour is the
  `RawByteChunk@0.1` fallback described above.

## Semantic pipe output

Under `--schema`, each source chunk is emitted as one or more R20b frames.
The wire format is composed inline by `PipeOut::pipe_forward_frame`
(`src/pipe_out.pdx`):

```
  +0   op          u8         = SP_OP_TYPED_RECORD (0x01)
  +1   ver         u8         = SP_VER (0x01)
  +2   flags       u16 LE     = SP_FLAG_HAS_HASH (0x0001)
  +4   payload_len u32 LE     = 32 + body_len
  +8   schema_hash [u8; 32]
  +40  body        [u8; body_len]
```

`body_len` is capped at `SP_MAX_RECORD_BODY = 4056` (`SP_MAX_PAYLOAD` 4088
minus the 32-byte hash). `PipeOut::pipe_forward_write` fans a 64 KiB read
chunk out into as many ≤ 4056-byte frames as needed.

**Schema-typed passthrough.** When `FileSchema::file_schema_query(handle)`
returns a non-zero pointer — i.e. the file declares a schema — the frame
body is the file's own bytes, unmodified, and `schema_hash` is the file's
declared 32-byte fingerprint. No re-encoding and no schema translation
happen: a downstream consumer that recognises the hash reads records, one
that does not reads bytes, and both are correct. This is what makes
`cat typed-file | consumer` work with no schema-aware code in cat.

**`RawByteChunk@0.1`** (declared in `caps.decl` under
`declares_output_schemas`) is the fallback for a file with no declared
schema, emitted by `src/raw_byte_chunk.pdx`:

| Field | Type | Description |
|-------|------|-------------|
| `offset` | `u64` LE | Byte offset of this record's first byte within the source file. Starts at 0 for each file argument (`rbc_reset` runs per file) and advances by the previous record's byte count. |
| `bytes` | `[u8]` | Up to `RBC_MAX_BODY = 4048` payload bytes (`SP_MAX_RECORD_BODY` 4056 minus the 8-byte offset field). |

The record is composed into `_rbc_scratch` as `[offset:u64 LE | bytes]` and
handed to `pipe_forward_frame` as the body, so on the wire a RawByteChunk
record is a normal typed frame whose `body_len` is `8 + bytes_len`.

Two v1.0 caveats, both stated in source:

- The `RawByteChunk@0.1` schema hash is a **placeholder**: the four
  little-endian qwords `0x1111111111111111`, `0x2222222222222222`,
  `0x3333333333333333`, `0x4444444444444444`, installed by `rbc_reset` and
  chosen to be obvious in a hex dump. It is to be recomputed from the
  canonical schema DDL; consumers keyed off this value will need to re-key.
- The frame stream is currently written into `TtySink` — the same sink as
  the text layer — because the `KIND_IPC_ENDPOINT` downstream binding has
  not landed. The call sites do not change when it does.

The frame constants above mirror `libpdx-semantic-pipe/src/envelope.pdx`
per the comments in `src/pipe_out.pdx`; that repo was not cloned for this
document, so the shared-library side of the contract is described here only
as cat's own source declares it.

## Exit codes

`cat` uses the collapsed exit-code vocabulary; the constants live in
`src/argv_dispatch.pdx` (`CAT_EXIT_*`) and are assembled at the tail of
`cat_dispatch`.

| Code | Name | Raised when |
|------|------|-------------|
| 0 | `CAT_EXIT_OK` | Every source was read and emitted successfully. |
| 2 | `CAT_EXIT_USAGE_ERROR` | Any argv parse failure (see below). |
| 3 | `CAT_EXIT_SYSTEM_ERROR` | Sink overflow from the render layer, a `pipe_forward_write` / `rbc_emit_chunk` failure, or `audit_stub_file_read` reporting the audit broker unreachable. |
| 4 | `CAT_EXIT_CAP_DENIED` | `file_open` returned 0 for a named path — file not found, or no read capability for it. |

Code 1 is unused. The parser's own return codes are internal and all
collapse to exit 2, with the offending `argv` index left in
`parse_error_arg_index`:

| Parser code | Name | Cause |
|-------------|------|-------|
| 1 | `PARSE_ERR_UNKNOWN_LONG_FLAG` | A `--` flag that is not exactly `--schema`. |
| 2 | `PARSE_ERR_UNKNOWN_OR_CLUSTERED_SHORT` | An unknown short flag, or more than one letter after a single hyphen. |
| 3 | `PARSE_ERR_POS_OVERFLOW` | More than `POS_MAX = 8` positionals, or an empty-string positional. |
| 4 | `PARSE_ERR_LONG_MISSING_NAME` | `--` with no name, or `--=…`. |
| 5 | `PARSE_ERR_NAME_TOO_LONG` | A positional longer than `NAME_MAX_LEN = 255` bytes. |

## Capabilities

Every public function in `src/*.pdx` — all 33 of them, including the
`cat_dispatch` entry point — carries the same annotation verbatim:

```
pub let cat_dispatch : (u64, u64) -> u64 !{mem} @{} =
  fn (argv: u64) (argc: u64) -> unsafe {
    effects: {mem}, capabilities: {},
```

`!{mem} @{}` — memory effects only, no capability effects — because at v1.0
every syscall-bearing edge is still an in-tree stub. The capabilities cat is
*granted at exec* are declared in `caps.decl`, which the shell validates
before the process starts:

```
requires:
  - KIND_USER
  - KIND_TTY(write)
  - KIND_PDXFS_FILE(read, <arg-path>)
  - KIND_IPC_ENDPOINT

declares_output_schemas:
  - RawByteChunk@0.1
```

`KIND_PDXFS_FILE` is narrowed per argument: `cat a b c` receives three
distinct read caps, one for each path, and can touch nothing else — no
wildcard subtree is ever granted. `KIND_TTY` is narrowed to `write` (no
read, no `tcsetattr`). `KIND_USER` identifies the reader for the audit tail;
`KIND_IPC_ENDPOINT` carries stdin and the semantic-pipe layer. A missing cap
in the received set exits 4; an *extra* cap is refused shell-side at exec, so
cat never sees it.

## Examples

Single file to the terminal — bytes verbatim, no transformation:

```
$ cat /etc/motd
Welcome to paideia-os.
```

Multi-file concatenation, strictly in argv order:

```
$ cat header.pdx body.pdx footer.pdx
<contents of header.pdx><contents of body.pdx><contents of footer.pdx>
```

Line numbering, right-justified in six columns and continuous across both
files (file two's first line is numbered 3, not 1):

```
$ cat -n a.txt b.txt
     1<TAB>alpha
     2<TAB>beta
     3<TAB>gamma
```

Non-printables made visible — useful on a byte-tainted file. Here the input
is `A`, TAB, `B`, `0x01`, LF:

```
$ cat -A tainted.dump
A^IB^A$
```

Schema-typed passthrough into a downstream consumer. If `data.records`
declares a schema, the consumer sees that schema's records byte-for-byte;
if not, it sees `RawByteChunk@0.1` records carrying `offset` + `bytes`:

```
$ cat --schema data.records | table
```

Stdin passthrough with zero positionals — no file is opened, so no
`FileReadRecord` is journaled:

```
$ grep foo log.txt | cat | wc -l
```

## Substrate posture

Six of the nine source modules ship deliberate, test-seedable stubs that
stand in for kernel and library substrates not yet landed. This is by
design at v1.0: correctness is asserted on observable I/O effects, not on
which side of the stub boundary a byte crossed, so migration to the real
substrates preserves every function signature and leaves the dispatcher,
argv, and render layers untouched.

| Module | File | Stubs | Blocked on |
|--------|------|-------|------------|
| `FileRead` | `src/file_read.pdx` | `sys_pdxfs_open` / `_read` / `_close` | `KIND_PDXFS_FILE` substrate |
| `StdinSource` | `src/stdin_source.pdx` | `sys_ipc_recv` | shell pipeline mint of `KIND_IPC_ENDPOINT` |
| `TtySink` | `src/tty_sink.pdx` | `KIND_TTY(write)` syscall (64 KiB `.bss` sink, `TTY_OUT_CAP = 65536`) | shell terminal cap handoff |
| `PipeOut` | `src/pipe_out.pdx` | `Passthrough::pipe_forward` | libpdx-semantic-pipe downstream binding |
| `FileSchema` | `src/file_schema.pdx` | `.pdxfs` schema-metadata lookup | `sys_pdxfs_getxattr` / cap-descriptor field |
| `AuditStub` | `src/audit_stub.pdx` | libpdx-audit `audit_begin` + `audit_record_output` + `audit_commit` | `svc.audit-journal` broker binding |

One consequence is visible in behaviour: `cat_dispatch` deliberately does
*not* reset the `FileRead` / `StdinSource` / `AuditStub` / `FileSchema`
tables, because those hold seed state the test harness populates before
dispatch. And because `TtySink` is a bounded buffer rather than a real
terminal, output beyond 64 KiB currently exits 3. The four `tests/*.pdx`
modules cover argv-order preservation, schema passthrough, bounded
streaming across a 128 KiB file, and the stdin path; each returns 0 on pass
and a distinct non-zero code per assertion so a harness can decode the
failure without logs.

Repository layout, release history, and per-issue notes:

```
caps.decl                  # exec-time capability manifest
deps.list                  # shared-lib deps (empty at v1.0)
manifest.pdxsig            # dual-signed package manifest
cat.pdxdoc                 # long-form doc, the `doc cat` back-end
design/architecture.md     # internal shape spec (argv grammar, pipeline)
src/entry.pdx              # Entry: _start + --version fast path
src/cat.ld                 # linker script (text/data/bss layout)
src/argv_dispatch.pdx      # ArgvDispatch: argv scan + top-level dispatcher
src/file_read.pdx          # FileRead: streaming open/read-chunk/close
src/stdin_source.pdx       # StdinSource: streaming stdin read
src/render.pdx             # Render: -n / -A transformations
src/tty_sink.pdx           # TtySink: bounded write sink
src/pipe_out.pdx           # PipeOut: semantic-pipe frame emitter
src/file_schema.pdx        # FileSchema: per-handle schema-hash lookup
src/raw_byte_chunk.pdx     # RawByteChunk: schemaless record emission
src/audit_stub.pdx         # AuditStub: per-file FileReadRecord gate
src/tool_ident.pdx         # ToolIdent: PDX_TOOL_NAME/VERSION externs
src/schema_wire.pdx        # SchemaWire: libpdx-schema-registry wire (#27)
src/pipe_emit.pdx          # PipeEmit: sys_semantic_send emission (#29)
tests/                     # correctness modules (see tests/README.md)
tools/build.sh             # assembles every src/ and tests/ .pdx
STATUS.md                  # milestone + issue rollup
CHANGELOG.md               # release history (v1.2.1-A)
MIRROR.md                  # package staging-push manifest
```

`bash tools/build.sh` assembles every `src/` and `tests/` `.pdx` file, then
links the `src/` objects (ENH-001, #17) via `src/cat.ld` into
`build-out/cat.elf`, using the `_start` entry point in `src/entry.pdx`
(`tests/*.pdx` are fixtures and are deliberately excluded from the link).
It resolves paideia-as from `$PAIDEIA_AS`, a sibling `paideia-os` checkout,
or `$PATH`, and requires version 0.21.0 or newer. Every source and test
file observes the
paideia-as conformance rules recorded in `design/architecture.md` §5:
PascalCase module basename, no `test` mnemonic, `cmp`-immediate-32 only,
`r11` as reserved scratch, zero-then-`mov_b` byte loads, and SysV
push/pop parity.

## See also

- [libpdx-argv](https://github.com/paideia-os/libpdx-argv) — the shared argv
  parser cat's in-tree byte scanner is byte-compatible with, and will
  migrate to (same `pos_ptrs` shape, same flag bit mask, same error codes).
- [libpdx-semantic-pipe](https://github.com/paideia-os/libpdx-semantic-pipe)
  — owner of the frame wire format and the passthrough path `PipeOut` stubs.
- [ls](https://github.com/paideia-os/ls) — sibling category-A coreutil.
- [doc](https://github.com/paideia-os/doc) — reads `cat.pdxdoc` to render
  `doc cat`, the long-form manual for this tool.

MIT — see [LICENSE](LICENSE).

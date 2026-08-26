# cat — enhancement plan (v1.x)

**Date:** 2026-08-25
**Scope:** `github.com/paideia-os/cat` at `v1.0.0` (`f75471c`)
**Method:** every claim below is grep-verified against the source tree in
this repo, or against `paideia-os/paideia-os` at HEAD. Line references are
to the tree as of the commit above.

---

## 1. Current state

`cat` ships nine `.pdx` modules (2381 lines under `src/`) implementing a
byte-pump with three output layers: a text layer (`-n` line numbering, `-A`
non-printable escaping), a semantic-pipe layer (`--schema`: schema-typed
passthrough or `RawByteChunk@0.1` fallback), and an audit layer (one
`FileReadRecord` per file argument, before the first byte). Four `.pdx` test
modules under `tests/` cover argv-order preservation, frame layout, bounded
streaming, and the stdin path. `manifest.pdxsig`, `caps.decl`, `deps.list`,
`cat.pdxdoc`, and `MIRROR.md` are present; the tree is tagged `v1.0.0` and
STATUS.md declares all 16 issues (#1–#16) LANDED.

The design is genuinely good. The argv grammar, the exit-code taxonomy, the
per-file capability narrowing, and the schema-passthrough-not-re-encoding
decision are all sound and worth keeping. The problem is not the design.

## 2. The load-bearing gap: this tree has never executed

`grep -rn "syscall" src/` returns **zero instruction-stream hits** — every
match is prose inside a comment or a `justification:` string. There is no
`_start`, no entry point, and no `.ld` linker script anywhere in the repo.
`tools/build.sh` iterates `src/*.pdx` emitting one `.o` per file via
`paideia-as build --emit elf64` and **never links**. There is therefore no
artifact this repository can produce that the kernel could load.

Six of the nine modules are explicitly test-seedable stubs, and README.md,
STATUS.md, and CHANGELOG.md all say so plainly. What none of them say is the
consequence: `file_open(path)` (`src/file_read.pdx:242`) never reads the path
argument at all — it draws handles FIFO from a seed table the test harness
pre-populated. `cat /etc/motd` is not slow or partial in this tree; it is
not a thing that can happen.

### 2.1 There are two divergent `cat`s

The `cat` a paideia-os user actually gets at HEAD is **not this repo**. It is
`paideia-os/paideia-os:src/user/cat.pdx` — 242 lines, self-contained, using
SC+ syscalls 0/1/2/3/60 directly, seeded into `/bin/cat` by
`src/kernel/boot/witness/bin_seeds.pdx` under R61.M1-002 (#1821). That binary
opens each `argv[i]`, streams it through a 4096-byte buffer to fd 1, and
writes `cat: <path>: not found\n` to fd 2 on a failed open.

The two implementations have disjoint strengths:

| | satellite `paideia-os/cat` | monorepo `src/user/cat.pdx` |
|---|---|---|
| Runs on paideia-os | no | yes (`/bin/cat`) |
| Real file I/O | no (seed table) | yes (`sys_open`/`read`/`close`) |
| Multi-file argv order | yes | yes |
| `-n` / `-A` | yes | no |
| `--schema` / semantic pipe | yes | no |
| Audit-first gate | yes (stub) | no |
| stderr diagnostics | no | yes |
| Output size ceiling | 64 KiB | none |

Neither is a superset. The v1.x wave's central decision is which tree becomes
canonical; §5 ENH-002 frames it. Everything else in this plan is downstream
of that choice, which is why ENH-002 is the only `L` that is not also a
prerequisite.

## 3. Doc-vs-source mismatches

Each verified by grep; README.md (refreshed in the recent techdoc pass)
already documents items (a) and (c) honestly — the stale claims live in
`cat.pdxdoc` and `design/architecture.md`.

**(a) `--help` / `--version` do not exist.** `cat.pdxdoc` §Flags opens with
"`--help` / `--version` follow the standard I3 flag vocabulary", and
`design/architecture.md` §1 repeats it. The long-flag parser at
`src/argv_dispatch.pdx:227-233` byte-compares exactly one string —
`s`,`c`,`h`,`e`,`m`,`a`,NUL — and anything else falls to
`cat_parse_unknown_long` → exit 2. Both flags currently exit 2.

*Disposition, and the reasoning behind it.* These two should not be treated
the same way. `--version` is worth **wiring up**: it is a handful of byte
compares plus one write, and a tool that cannot state its own version is
un-diagnosable in the field — `pkg` can report what it *installed*, but not
what a given `/bin/cat` inode actually *is* after a partial upgrade or a
`--from-source` build. That gap is exactly the kind of thing the two-key
signing policy exists to make legible, so leaving it unanswerable undercuts
a stated pillar. Note honestly that the "standard across the org" framing in
`cat.pdxdoc` is not yet true in practice: grepping the nine shipping tools in
`src/user/` finds no `--version` implementation in any of them, so cat would
be establishing the convention, not conforming to one. That makes it a
coordination question, flagged in §6.

`--help`, by contrast, should be **stripped from the man page**. The org
already has a designed answer — `doc cat` reads `cat.pdxdoc`, and the `doc`
tool exists precisely so that long-form text lives in one place. Compiling a
second copy of the flag table into every tool's ELF duplicates the
`.pdxdoc` bytes across fourteen binaries and creates fourteen opportunities
for the in-binary text to drift from the canonical file. The
semantically-queryable-terminal pillar points the same way: help should be a
queryable artifact, not a string constant. Strip the claim; keep `doc cat`.

**(b) `--schema` refusal semantics are wrong, and self-contradictory.**
`cat.pdxdoc` §Flags describes `--schema` as "Force schema-typed passthrough
even when the input file carries no schema hash" and then, two lines later,
"Refuses (exit 2) if the file has no readable `.pdxfs` metadata" — those
cannot both hold. The implementation does neither: `cat_dispatch`
(`src/argv_dispatch.pdx:449-489`) branches on `file_schema_query(handle)`
and routes a zero result to `rbc_reset` + `rbc_emit_chunk`, i.e. the
`RawByteChunk@0.1` fallback. The source behaviour is the right one — a
downstream consumer can still window an untyped stream by byte range — so
the doc is what must change.

**(c) `libpdx-argv` is claimed but not linked.** STATUS.md:15 records
M1-002 as "argv surface **via libpdx-argv** … LANDED", and issue #2 carries
the same title. Source has no such dependency: `cat_parse_argv`
(`src/argv_dispatch.pdx:189-330`) is a hand-rolled inline byte scanner, and
`deps.list` declares the v1.0 dep set empty in so many words. The repo's own
`.plans/m1-002-notes.md` contains a section headed "Why not libpdx-argv at
M1" explaining the deliberate deviation, and `design/architecture.md` §2
schedules the migration "at cat.M3" — cat.M3 landed (#8, #9, #10) and did
not migrate. So the deviation is documented in the plans and contradicted in
the status rollup.

*Disposition.* Both halves, in that order. STATUS.md as written is simply
false and costs nothing to fix (ENH-006). The migration itself is also worth
doing rather than retracting: six coreutils each hand-rolling a `--` scanner
is six places a clustered-flag or empty-positional bug can hide, and one
shared parser is one audit surface — the same single-canonical-implementation
argument the org already accepted when it created the libpdx-* repos. But it
is explicitly sequenced *after* the entry point lands (ENH-007 deps ENH-001),
because refactoring the parser inside a binary that cannot run replaces a
verified-by-fixture component with an unverified one and gains nothing until
something can execute it.

**(d) stderr is claimed and never written.** `design/architecture.md` §1
lists "**stderr:** diagnostics (unreadable file, cap denied, sink
overflow)". No module writes a diagnostic anywhere; failures surface only as
process exit codes. This is also a live regression against the tool that
actually ships — the monorepo `cat` does emit `cat: <path>: not found`.

## 4. Gap vs what paideia-os needs at HEAD

**Relative paths are already solved kernel-side — do not re-solve them here.**
R86.M1-005 (#1958) changed `vfs_open` (`src/kernel/core/fs/vfs_open.pdx:96-103`)
to load `cwd` from `[_current_tcb + 160]` (`TASK_OFF_CWD`) at both
`path_resolve` call sites instead of passing a hardcoded 0, so a path with no
leading `/` now resolves against the calling task's current directory.
`sys_chdir` (sysno 85) and `sys_getcwd` (sysno 86) are dispatched at
`src/kernel/core/syscall/dispatch.pdx:2353-2385`.

The consequence for cat is a pleasant one: cat needs **no** path
normalization, no cwd tracking, and no `sys_getcwd` call of its own. It gets
correct relative-path behaviour for free the moment `file_open` becomes a
real `sys_open` (ENH-001). This is recorded explicitly so that a future
implementer does not build a redundant normalizer that would then diverge
from `path_resolve`'s `.`/`..` handling.

**The 64 KiB output ceiling.** `TtySink` is a `.bss` buffer with an overflow
guard at `src/tty_sink.pdx:231` (`cmp rcx, 65536; jge`), returning
`TTY_SINK_OVERFLOW` → exit 3. So `cat` on any file larger than 64 KiB fails
today. This sits oddly beside the headline claim that a 1 GiB file streams as
16384 chunks: that is true of the read side and false of the write side, and
the write side is the one the user observes.

**`NAME_MAX_LEN = 236`** (`src/argv_dispatch.pdx:141`) is narrower than the
kernel's own limit — `SYS_CHDIR_PATH_MAX`, `SYS_STAT_PATH_MAX`,
`SYS_MKDIR_PATH_MAX`, and `path.pdx`'s `PATH_MAX` are all 256. cat will
reject with exit 2 a range of paths the kernel would happily resolve.

**`RawByteChunk@0.1`'s fingerprint is a debug pattern.** `rbc_reset` installs
four literal qwords `0x1111111111111111` / `0x2222…` / `0x3333…` /
`0x4444…` as the 32-byte schema hash, and the source says outright it was
chosen to be obvious in a hex dump. Meanwhile `caps.decl`
`declares_output_schemas` and `manifest.pdxsig` §5 publish
`RawByteChunk@0.1` to consumers as a real contract, inside a manifest whose
whole purpose is a two-key attestation of what this package emits. Any
consumer keying off the advertised hash must re-key later. Advertising a
placeholder through a signing envelope is the one item here that is
supply-chain-shaped rather than merely incomplete.

## 5. Issue plan

Nine issues, filed against milestone **"Enhancement v1.x — cat"**. Sequencing
matters more than the count: ENH-001 unblocks five of the other eight.

| ID | # | Title | Effort | Deps |
|----|---|-------|--------|------|
| ENH-001 | #17 | Real syscall substrate: `_start`, linker script, linked ELF | XL | none |
| ENH-002 | #22 | Reconcile with monorepo `src/user/cat.pdx` — one canonical cat | L | #17 |
| ENH-003 | #23 | stderr diagnostics on open failure / cap denial / I/O error | S | #17 |
| ENH-004 | #24 | Remove the 64 KiB output ceiling in `TtySink` | M | #17 |
| ENH-005 | #20 | Wire `--version`; strip `--help` and fix `--schema` text in `cat.pdxdoc` | S | none |
| ENH-006 | #18 | Correct the libpdx-argv claim in STATUS.md | XS | none |
| ENH-007 | #25 | Migrate `cat_parse_argv` to libpdx-argv; update `deps.list` + manifest | M | #17, #18 |
| ENH-008 | #21 | Replace the `RawByteChunk@0.1` placeholder hash with the canonical DDL hash | S | none |
| ENH-009 | #19 | Raise `NAME_MAX_LEN` from 236 to 255 to match kernel `PATH_MAX` | XS | none |

#20, #18, #21, and #19 are independent of the substrate work and can land
immediately.

## 6. Companion work owed by the paideia-os monorepo

Not filed from this repo; recorded here for the coordinating pass.

1. **Seeding.** If ENH-002 resolves toward the satellite tree, the built
   `cat.elf` must be seeded into `src/kernel/boot/witness/bin_seeds.pdx`,
   replacing the R61.M1-002 (#1821) `/bin/cat` entry, with a matching
   `klog_s1_d1` fingerprint.
2. **Substrate gates named in this repo's own docs**, none of which exist at
   HEAD: `KIND_PDXFS_FILE` (R42), `sys_pdxfs_getxattr` for `.pdxfs` schema
   metadata, shell.M2 `KIND_IPC_ENDPOINT` pipeline mint, shell.M4 `KIND_TTY`
   handoff, and the `svc.audit-journal` broker (R49-PREP-006). Note that the
   monorepo `cat` needs none of these — it uses SC+ syscalls 0/1/2/3 — so
   ENH-001 should be scoped against the syscalls that exist rather than
   waiting on the five that do not.
3. **`--version` as an org convention.** No tool in `src/user/` implements
   it. Worth one decision applied to all fourteen repos rather than fourteen
   independent ones.

## 7. Verdict on the v1.0.0 tag

**Not defensible; the plan should walk it back to `v0.x` and call STATUS.md's
claims aspirational.**

This is not a judgement about quality — the design work here is careful and
mostly correct, and the honesty of README.md's own caveats is a credit to the
tree. It is a judgement about the word *released*. STATUS.md states "`cat` is
*released* at v1.0.0 per the milestone rubric," and `CHANGELOG.md` calls it
"the first signed release." A tree that emits no linkable binary, executes no
syscall, and whose `file_open` ignores its path argument has not shipped a
tool; it has shipped a specification with an unusually rigorous set of
fixtures. Both signature blocks in `manifest.pdxsig` additionally read
`PENDING`, so the package could not install even if it existed.

The milestone rubric was satisfied as written. That is the finding: the rubric
lets M1–M5 close without anything ever running, and cat is the first tool to
demonstrate it. Retagging to `v0.5.0`, retitling STATUS.md's release line, and
restoring `v1.0.0` when ENH-001 and ENH-002 land keeps the version number
meaning what the rest of the org assumes it means.

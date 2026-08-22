# cat.M5-002 — implementation notes

**Issue:** #16 — pkgs.paideia-os mirror push
**Upstream doc:** `design/tooling/plan.md` §6.3 + §6.4 + §9.3
(paideia-os), and `design/tooling/r49-r50-plan.md` §5.5 (M5 line).

## What landed

- `MIRROR.md` — mirror-push manifest at repo root. Documents the
  staging-tree layout (`pkgs.paideia-os/staging/cat/1.0/`), the
  pkg.tar composition (14 file paths, tar-position byte-sorted),
  the pre-tar sha2-256 witness over each shipped file, the
  reproducibility script the signing bot uses to re-pack pkg.tar,
  and the post-push verification chain at the user side.
- STATUS.md — M5-002 row flipped to LANDED; M5 rollup closed;
  current-milestone header advanced to "M5 CLOSED — released".
- README.md — status line advanced to v1.0.0 released; MIRROR.md /
  manifest.pdxsig / cat.pdxdoc / CHANGELOG.md added to the layout
  block.

## Design decisions

**The mirror push is an event, not an artifact.** Per plan.md §9.3,
the physical push into `pkgs.paideia-os/staging/` is triggered by
`paideia-as release --sign` running against the frozen source at the
v1.0.0 tag. That toolchain path is blocked on v0.33-crypto (author
signature) and on T-INFRA-001 (the pkgs.paideia-os repository host)
per the substrate posture in `manifest.pdxsig` and reiterated in
MIRROR.md §1. The M5-002 deliverable in THIS repo is therefore the
push manifest — the pre-computed payload that WILL be pushed once
the infrastructure exists — not the push itself. This matches how
`manifest.pdxsig` shipped at M5-001 with `PENDING` signature bytes:
the shape is real, the wire event is deferred.

**The mirror-push manifest lives IN the tool repo, not in a
separate `pkgs.paideia-os` mirror repo.** Alternative was to add
files under `pkgs/staging/cat/1.0/`. Rejected because (a) it would
leak the mirror's file layout into every tool's tree (every future
tool would carry a `pkgs/staging/<tool>/<version>/` subtree — the
mirror should own its own layout), and (b) the signing bot builds
the tree at push time from `paideia-as release --sign` output, so a
committed `pkgs/staging/` tree in the tool repo would drift from
the bot's output and become a review liability. A single `MIRROR.md`
at repo root, review-friendly and diff-friendly, is the right shape.

**The pkg.tar file list is FROZEN at v1.0.** The 14 files listed in
MIRROR.md §3 are what the pkg archive ships — every other file in
the repo (tests/, .plans/, design/, README.md, STATUS.md,
CHANGELOG.md, MIRROR.md itself) is development artifact and does
not go on-wire. The exclusion list is enumerated explicitly so a
future contributor cannot accidentally leak a `.plans/` file into
the pkg by naming their file oddly. src/*.pdx IS included at v1.0
because plan.md §D4 keeps the `--from-source` trust-zero path open;
a follow-up release can drop src/ once a stable binary format
exists.

**Reproducibility is a hard requirement.** MIRROR.md §5 spells out
the `tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@...`
invocation that the signing bot uses to re-pack pkg.tar
deterministically. Without this, the sha3-256 in `manifest.pdxsig`
§4 (once v0.33-crypto lands) would depend on the file system's
`readdir()` order and the reviewer's clock — either of which
breaks the two-key policy by making the signature verifiable only
on the signer's exact machine. The `--mtime=@1755820800` is the
release timestamp in Unix seconds (2026-08-22T00:00:00Z).

**v1.0.0 tag placement.** The git tag lands on the M5-002 commit
(the commit that adds MIRROR.md + closes M5). This is the correct
placement because:
- The `manifest.pdxsig` sha in MIRROR.md §4 must include the
  version of manifest.pdxsig that references `git_tag: v1.0.0`.
  Tagging on an earlier commit would make the tag point to a
  source tree that does not yet declare its own tag identity.
- MIRROR.md §5's reproducibility script `git checkout v1.0.0`
  expects the exact tree the release-manifest was built over.

## Compliance

Same as M5-001 — text artifacts only, no paideia-as conformance rules
apply. No source or test .pdx files touched.

## Files touched

- Added: `MIRROR.md` at repo root
- Modified: `STATUS.md` (M5-002 row + M5 close + header)
- Modified: `README.md` (status line + layout block)
- Added: `.plans/m5-002-notes.md` (this file)
- Tagged: `v1.0.0` on this commit

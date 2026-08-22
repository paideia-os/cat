# cat — MIRROR.md

Staging-mirror push manifest for `pkgs.paideia-os/staging/cat/1.0/`,
per invariant §9.3 in `design/tooling/plan.md` and repository model
§6.3 (paideia-os).

**Wave:** R50
**Release:** v1.0.0
**Push target (staging):** `https://pkgs.paideia-os/staging/cat/1.0/`
**Promotion target (post-review):** `https://pkgs.paideia-os/main/cat/1.0/`

---

## 1. Substrate posture — the push is blocked

The physical push of the artifacts below into `pkgs.paideia-os` is
BLOCKED on two paideia-os infrastructure issues that are not yet
landed at HEAD:

- **T-INFRA-001** — dual-sign package repository infrastructure
  (`pkgs.paideia-os`) — the HTTPS package host itself. Filed against
  the paideia-os meta repo per `design/tooling/plan.md` §10.
- **T-INFRA-002** — signing bot host + policy for `paideia_root_pk`.
  This is the automated re-sign step that flips
  `manifest.pdxsig` §7 from `PENDING` bytes to the root ML-DSA-65
  signature over the same §1..§5 byte range the author signed.

Consequence: the `cat.M5-002` deliverable committed to THIS repo is
the pre-computed staging-push manifest — the payload that WILL be
pushed once T-INFRA-001 exists and the payload that WILL be re-signed
in-place once T-INFRA-002 exists. This mirrors how the R42 / shell.M2
/ shell.M4 / R49-PREP-006 stubs in `src/*.pdx` stand in for kernel
substrates: the shape is real, the crossing is deferred.

`cat.M5-002` closes on the manifest below being reviewed + the v1.0.0
git tag existing. The physical push is a separate event tracked in
T-INFRA-001 against paideia-os.

---

## 2. Push payload (the mirror tree)

The staging tree contains three files at the tool + version path:

```
pkgs.paideia-os/staging/cat/1.0/
  pkg.tar               # tar archive of the shipped tree (see §3)
  manifest.pdxsig       # dual-signed manifest (author-signed today;
                        # root-signed at promotion by signing bot)
  cat.pdxdoc            # long-form doc, installed to
                        # /system/doc/cat.pdxdoc at pkg install time
```

`pkg install cat` reads the manifest, verifies BOTH signatures,
verifies the pkg.tar hash against manifest §4, unpacks pkg.tar into
`/pkgs/cat-1.0.0/`, and symlinks `/bin/cat` per plan.md §6.4.

Promotion from `staging/` to `main/`:

1. Signing bot receives the push; a human reviewer confirms the git
   tag `v1.0.0` in `github.com/paideia-os/cat` matches the pkg.tar
   contents (via re-run of the reproducibility script §5 below).
2. Signing bot re-signs `manifest.pdxsig` §7 with `paideia_root_pk`.
3. Signing bot moves the tree from `staging/cat/1.0/` to
   `main/cat/1.0/`; `pkg install cat` on user machines picks it up
   on the next `pkg upgrade`.

---

## 3. pkg.tar composition

`pkg.tar` is a `tar` archive of the following paths, in tar-position
byte-sorted order (POSIX ustar, no extended headers, no compression;
the pkg tool decompresses at install time only if a `.gz` / `.zst`
sibling is served — v1.0 ships uncompressed for reproducibility):

```
LICENSE
caps.decl
deps.list
manifest.pdxsig
cat.pdxdoc
src/argv_dispatch.pdx
src/audit_stub.pdx
src/file_read.pdx
src/file_schema.pdx
src/pipe_out.pdx
src/raw_byte_chunk.pdx
src/render.pdx
src/stdin_source.pdx
src/tty_sink.pdx
```

The pkg.tar EXCLUDES:
- `tests/` — development artifacts, not runtime.
- `.plans/` — implementation notes, not runtime.
- `design/` — design docs, not runtime (the substantive design is in
  the paideia-os meta repo; `design/architecture.md` in this repo is
  a thin pointer document).
- `README.md`, `STATUS.md`, `CHANGELOG.md`, `MIRROR.md` — repo
  metadata, not runtime.

At v1.0, `src/*.pdx` is included because the pkg install flow at
plan.md §6 supports `pkg install --from-source cat` for the
trust-zero path (rebuild from source, verify against the author-tag
hash). Once `pkg install --from-source` is deprecated (post-Tier-3,
when a stable binary format exists), a follow-up release can drop
`src/` from pkg.tar and ship only the built binary.

---

## 4. Pre-tar content hashes (sha2-256, over the shipped tree at HEAD)

The signing bot recomputes `hash_pkg_tar` after packing; the source
hashes below are the input witness so a reviewer can spot a drift
between the author push and the signing-bot tar.

```
LICENSE            5d10906e3e9407412fd51592e3dd968251a4797b8ffdcc9e862d8fb1f3925e2b
caps.decl          6fecbbcbb808f983013bb43fef6e4eac8f7f187254098c7f33295d79cbcb20c6
deps.list          958f1923b7bf41869393931e1b056dee33af4c5fa0225580a9bc415554099a77
manifest.pdxsig    806d21dd31ea8246ddb4f6631307a961fe62a5aa99b40ca2e778c537726cfe69
cat.pdxdoc         a5f1643f208cbd129ff6e1d125189af732390ca98a4736e493ef3ffb221db36f
src/argv_dispatch.pdx    f469c2d1d5eb4566b72f0e671e445ce26f094e26e2722569282d5921b03c575f
src/audit_stub.pdx       fa54b463e2889a83163dbe77db790ad45e8ebd20cad14ac9d7709154d5089b4e
src/file_read.pdx        156125b2bb9158cce7fbfdc97eaaff2a054734d8c7ec041c825054b37fb4f28f
src/file_schema.pdx      386b61957578326cb18137272b2c4bb8aa4b4f5f0cd77d6d19006be76369b43e
src/pipe_out.pdx         e2fbff6e39e67f2dc3edcda4cbd2bf3f0e5d01da55899445f6a64ba73c1e2736
src/raw_byte_chunk.pdx   37cd03fa05353c4b6abddc5748d907f46367c0db0d144a52b114f6d7f1219c06
src/render.pdx           66ee1ceb21b277c9c30614972762bc4396201c2ca2c54cd7c14738e83399a618
src/stdin_source.pdx     7534a738a743bc98c06ee5325f2a6bd1c258ff62e22b90b486e7cba41e2daac8
src/tty_sink.pdx         bc458b562c5128b6c74a35802edb501d231ef9b1865eb083ec5e32d30aa6a9f0
```

Note: the sha of `manifest.pdxsig` is computed OVER the file as
committed here (§6 + §7 = `PENDING`). Once the signing bot fills in
§6 + §7 with real signatures at promotion, the file's sha changes;
that is expected and is why the on-wire manifest carries an
`index.pdxsig` (per plan.md §6.3) that lands over the FINAL bytes.
The hash above is the reviewer's pre-signing witness only.

---

## 5. Reproducibility script (for the signing bot's tar re-pack)

The signing bot re-packs pkg.tar with:

```sh
cd cat/                              # repo root at git tag v1.0.0
git checkout v1.0.0                  # exact tree
tar --sort=name \
    --owner=0 --group=0 --numeric-owner \
    --mtime=@1755820800 \            # v1.0 release timestamp (UTC)
    -cf pkg.tar \
    LICENSE caps.decl deps.list manifest.pdxsig cat.pdxdoc \
    src/argv_dispatch.pdx src/audit_stub.pdx src/file_read.pdx \
    src/file_schema.pdx src/pipe_out.pdx src/raw_byte_chunk.pdx \
    src/render.pdx src/stdin_source.pdx src/tty_sink.pdx
sha256sum pkg.tar
```

The reviewer verifies the resulting `sha256sum pkg.tar` matches the
value in `manifest.pdxsig` §4 after the signing bot re-emits with
paideia-as v0.33-crypto. Reproducibility is a hard-requirement of
the two-key policy: a signature over a non-reproducible tar is a
supply-chain crack.

---

## 6. Post-push verification (once T-INFRA-001 lands)

After the push lands in `pkgs.paideia-os/staging/cat/1.0/`, the
verification chain at the user side is:

```sh
pkg install cat                      # fetches staging tree
# → pkg fetches manifest.pdxsig
# → pkg verifies author_signature (§6) against author_pk fingerprint
# → pkg verifies root_signature   (§7) against paideia_root_pk
#   fingerprint (WILL FAIL at v1.0 because §7 is PENDING; promotion
#   to main/ replaces §7 with the real root signature)
# → pkg fetches pkg.tar; verifies sha3-256 against manifest.pdxsig §4
# → pkg unpacks pkg.tar into /pkgs/cat-1.0.0/
# → pkg symlinks /bin/cat → /pkgs/cat-1.0.0/bin/cat (once cat is
#   built; at v1.0 the src/*.pdx are shipped for --from-source only)
```

`pkg install --from-source cat` at v1.0 works today (bypasses §6/§7
verification per plan.md §D4; still verifies the source-tree root
commit matches the author tag).

---

## 7. Milestone-close signal

`cat.M5-002` closes on the following three artifacts existing:

1. This file (`MIRROR.md`) at repo root — documents the push payload.
2. `manifest.pdxsig` at repo root — the author-signed manifest.
3. `git tag v1.0.0` on the commit that adds this file — marks the
   frozen source tree the manifest hashes over.

M5 closes on M5-002 closing. On M5 close, `cat` is *released* per
the milestone rubric — the physical push to `pkgs.paideia-os` is a
downstream event tracked in T-INFRA-001 + T-INFRA-002 against
paideia-os, not against this repo.

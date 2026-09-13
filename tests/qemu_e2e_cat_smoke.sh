#!/usr/bin/env bash
# tests/qemu_e2e_cat_smoke.sh — cat #32 end-to-end smoke placeholder
#
# Wave: v1.2.0-A batch (Closes cat #32)
#
# Purpose
# -------
# Assert that `cat FOO` — invoked from the shell inside a booted
# QEMU guest — prints the byte string `FOO` on the guest's serial
# stdout. This is the single load-bearing correctness fingerprint
# for the v1.1-A substrate flip (paideia-os/cat #28): if the real
# sys_open + sys_read + sys_write path fabricated into entry.pdx is
# wired end-to-end (kernel syscall table → tmpfs backing → tty0
# writer), the payload byte survives every layer and lands in the
# host-visible serial stream.
#
# Two invariants the test asserts once the substrate exists:
#   1. Guest boots to shell without regression.
#   2. `cat FOO` (where FOO is a pre-seeded tmpfs file containing
#      the literal 3-byte payload `FOO\n`) yields `FOO` on the
#      captured serial stream inside a bounded time window.
#
# Substrate posture at v1.2.0-A (PLACEHOLDER — skip path)
# -------------------------------------------------------
# The physical run is BLOCKED on three preconditions that are not
# reachable from this satellite alone:
#
#   (a) tools/build.sh in this repo produces build-out/cat.elf but
#       the monorepo's bin_seeds pathway still consumes the in-tree
#       src/user/cat.pdx build product (paideia-os HEAD is Phase-A
#       of design/user/in-tree-vs-satellite-transition.md). Phase-B
#       flips bin_seeds to read the manifest at
#       tools/bin_seeds.manifest — until then, this satellite's
#       cat.elf never reaches /bin/cat inside the guest.
#
#   (b) The shell inside the guest (paideia-os in-tree src/user/
#       shell.pdx at HEAD) does exec /bin/cat, but the argv
#       tokenizer is the pre-quoting bring-up shell (design/user/
#       in-tree-vs-satellite-transition.md §3 shell row); a `cat
#       FOO` invocation works because it's whitespace-only, but
#       any escaping / quoting shape falls off the tokenizer's
#       supported grammar. This smoke deliberately picks the
#       simplest command form so the shell tokenizer transition is
#       not a blocker.
#
#   (c) tools/run-qemu.sh is a paideia-os monorepo tool, not a
#       satellite tool. Invoking it requires either a sibling
#       paideia-os checkout at ../paideia-os or a $PAIDEIA_OS_ROOT
#       env override. This script probes for both and falls to a
#       SKIP: with a diagnostic if neither resolves.
#
# Behaviour at v1.2.0-A
# ---------------------
# When run, this script:
#   1. Locates the paideia-os monorepo root via $PAIDEIA_OS_ROOT
#      (env), or ../../../ (walk up from tests/), or
#      $HOME/Development/PaideiaOS. Fails soft with SKIP: if none
#      resolves.
#   2. Verifies $PAIDEIA_OS_ROOT/tools/run-qemu.sh exists +
#      executable. SKIP: if not.
#   3. Verifies the bin_seeds cutover manifest is present at
#      $PAIDEIA_OS_ROOT/tools/bin_seeds.manifest AND names this
#      satellite as the /bin/cat source. SKIP: with a diagnostic
#      pointing at design/user/in-tree-vs-satellite-transition.md
#      §4 if not (Phase-B has not landed).
#   4. Builds cat.elf locally via ./tools/build.sh (this repo);
#      fails hard on build error.
#   5. Invokes run-qemu.sh with a boot-cmd seeding /tmp/FOO with
#      the literal "FOO\n" and executing `cat /tmp/FOO` from the
#      first-user-shell prompt, redirected to a captured log.
#   6. Greps the captured log for the exact byte string `FOO` on
#      a line by itself. PASS on match; FAIL on absence with the
#      log tail printed to stderr.
#
# Exit codes:
#   0  — PASS (fingerprint bytes observed)
#   1  — FAIL (bytes not observed / stream corrupted)
#   77 — SKIP (substrate precondition unmet; per autotools skip
#        convention so a CI harness can distinguish "not yet"
#        from "regression")
#
# Runtime notes for the eventual live path:
#   * The `cat /tmp/FOO` argv reaches _start in entry.pdx as
#     argc=2, argv=[<program>, "/tmp/FOO"]. The file loop opens
#     "/tmp/FOO" (fd = 3), sys_read yields 4 bytes ("FOO\n"),
#     sys_write(1, cat_buf, 4) drops those 4 bytes on tty0's
#     serial mux → the host QEMU log line contains `FOO`.
#   * had_error stays 0 (single positional, opens cleanly), so
#     sys_exit(0) — the shell's next prompt marks the invocation
#     boundary in the captured log.

set -euo pipefail

# ---- Skip helper -----------------------------------------------------
skip() {
    echo "SKIP: $*" >&2
    exit 77
}

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# ---- Precondition 1: locate paideia-os monorepo root ----------------
PAIDEIA_OS_ROOT="${PAIDEIA_OS_ROOT:-}"
if [ -z "$PAIDEIA_OS_ROOT" ]; then
    # Try walking up from this script's dir.
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    for cand in \
        "$script_dir/../../.." \
        "$script_dir/../../../.." \
        "$HOME/Development/PaideiaOS"
    do
        if [ -f "$cand/tools/run-qemu.sh" ]; then
            PAIDEIA_OS_ROOT="$(cd "$cand" && pwd)"
            break
        fi
    done
fi
if [ -z "$PAIDEIA_OS_ROOT" ] || [ ! -d "$PAIDEIA_OS_ROOT" ]; then
    skip "paideia-os monorepo root not found; set PAIDEIA_OS_ROOT or clone at \$HOME/Development/PaideiaOS"
fi

# ---- Precondition 2: run-qemu.sh present ----------------------------
RUN_QEMU="$PAIDEIA_OS_ROOT/tools/run-qemu.sh"
if [ ! -x "$RUN_QEMU" ]; then
    skip "run-qemu.sh not found or not executable at $RUN_QEMU"
fi

# ---- Precondition 3: bin_seeds satellite cutover manifest present ---
# design/user/in-tree-vs-satellite-transition.md §4 Phase-B introduces
# tools/bin_seeds.manifest. Until it exists, this satellite's cat.elf
# never reaches /bin/cat inside the guest — a run would be a false
# positive against the in-tree body, not against ours.
BIN_SEEDS_MANIFEST="$PAIDEIA_OS_ROOT/tools/bin_seeds.manifest"
if [ ! -f "$BIN_SEEDS_MANIFEST" ]; then
    skip "bin_seeds satellite cutover not landed (missing $BIN_SEEDS_MANIFEST); see design/user/in-tree-vs-satellite-transition.md §4 Phase-B"
fi
if ! grep -qE '^/bin/cat[[:space:]]+sat[[:space:]]' "$BIN_SEEDS_MANIFEST"; then
    skip "bin_seeds manifest does not route /bin/cat to satellite; see design/user/in-tree-vs-satellite-transition.md §4 Phase-B"
fi

# ---- Build cat.elf locally ------------------------------------------
CAT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$CAT_ROOT"
if [ ! -x "./tools/build.sh" ]; then
    fail "cat repo build.sh missing at $CAT_ROOT/tools/build.sh"
fi
echo "[smoke] building cat.elf via $CAT_ROOT/tools/build.sh"
./tools/build.sh
if [ ! -f "$CAT_ROOT/build-out/cat.elf" ]; then
    fail "build.sh completed but build-out/cat.elf not produced"
fi

# ---- Invoke run-qemu with the fingerprint command -------------------
# The exact serial-log capture idiom is monorepo tools/run-qemu.sh's
# responsibility; this script drives it with a boot-cmd hook so the
# first-user shell executes `cat /tmp/FOO` (tmpfs pre-seeded with
# "FOO\n" by init) and exits.
LOG="$(mktemp -t cat_smoke.XXXXXX.log)"
trap 'rm -f "$LOG"' EXIT

echo "[smoke] running QEMU: cat /tmp/FOO -> expect 'FOO' on serial"
# The exact env / arg surface here is deliberately conservative; the
# run-qemu.sh caller composes the boot-cmd and the tmpfs pre-seed.
PAIDEIA_CMD="cat /tmp/FOO" \
PAIDEIA_TMPFS_SEED="/tmp/FOO=FOO\n" \
"$RUN_QEMU" -serial "file:$LOG" -no-reboot -display none \
    < /dev/null > /dev/null 2>&1 || true

# ---- Assert the fingerprint bytes appear ----------------------------
if grep -qE '^FOO$' "$LOG"; then
    echo "PASS: 'FOO' observed on serial stream"
    exit 0
fi

echo "FAIL: 'FOO' not observed in captured log; last 40 lines:" >&2
tail -n 40 "$LOG" >&2 || true
exit 1

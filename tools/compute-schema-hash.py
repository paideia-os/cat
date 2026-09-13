#!/usr/bin/env python3
# tools/compute-schema-hash.py -- cat.ENH-008 (paideia-os/cat#21)
#
# Re-derive the canonical schema-hash constant baked into
# src/raw_byte_chunk.pdx (RBC_SCHEMA_HASH / _rbc_schema_hash).
#
# Usage:
#   python3 tools/compute-schema-hash.py
#
# Prints the canonical DDL (byte-exact) followed by:
#   * SHA-256 hex digest
#   * The four little-endian u64 words consumed by rbc_reset's four
#     `mov rax, 0x...` immediates (in slot order q0/q1/q2/q3 -> stored
#     at [_rbc_schema_hash + 0/8/16/24]).
#
# Diff the printed qwords against the four movabs immediates in
# src/raw_byte_chunk.pdx :: rbc_reset. Divergence = the constant is
# stale w.r.t. the canonical DDL and must be re-installed.
#
# Migration to BLAKE3-truncated fingerprint (the final form named in
# design/tooling/r49-r50-plan.md): swap the hashlib.sha256 call for
# blake3.blake3 (or hashlib.blake2b(digest_size=32) as a stdlib
# interim) and re-run; no consumer signature edit is needed because
# _rbc_schema_hash is emitted verbatim as the 32-byte R20b schema_hash
# prefix.

import hashlib
import struct
import sys

DDL = b"RawByteChunk@0.1\noffset:u64\nbytes:[u8]\n"

def main() -> int:
    digest = hashlib.sha256(DDL).digest()
    if len(digest) != 32:
        print("unexpected digest length", file=sys.stderr)
        return 2
    qwords = struct.unpack("<4Q", digest)
    print("canonical DDL bytes (repr):")
    print("  " + repr(DDL))
    print("SHA-256 hex (32 bytes):")
    print("  " + digest.hex())
    print("Little-endian u64 slot view (order: rbc_reset stores):")
    for i, q in enumerate(qwords):
        print("  q%d = 0x%016X" % (i, q))
    return 0

if __name__ == "__main__":
    sys.exit(main())

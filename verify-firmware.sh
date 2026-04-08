#!/usr/bin/env bash

# ─────────────────────────────────────────────────────────────────
#  VERIFY-FIRMWARE.SH
#  Verifies firmware signature and CRC32 in a .nvpfwimage file.
#  Logic ported from Python cryptography implementation.
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

# Configuration
MAGIC=0x242666A0
HEADER_SIZE=2048
MIN_SIGNATURE_SIZE=64
MAX_SIGNATURE_SIZE=72

OPENSSL_BIN="${OPENSSL_BIN-openssl}"

usage() {
    echo "Usage: $0 --image <image.nvpfwimage> --public-key <public_key.pem>"
    echo ""
    echo "Options:"
    echo "  --image       Path to the .nvpfwimage file"
    echo "  --public-key  Path to the public key (PEM format)"
    exit 1
}

IMAGE=""
PUBLIC_KEY=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --image) IMAGE="$2"; shift 2 ;;
        --public-key) PUBLIC_KEY="$2"; shift 2 ;;
        *) usage ;;
    esac
done

if [[ -z "$IMAGE" || -z "$PUBLIC_KEY" ]]; then
    usage
fi

# Check files exist
if [ ! -f "$IMAGE" ]; then
    echo "Error: Image file not found -> $IMAGE" >&2
    exit 1
fi

if [ ! -f "$PUBLIC_KEY" ]; then
    echo "Error: Public key file not found -> $PUBLIC_KEY" >&2
    exit 1
fi

FILE_SIZE=$(stat -f%z "$IMAGE" 2>/dev/null || stat -c%s "$IMAGE")

if [ "$FILE_SIZE" -lt "$HEADER_SIZE" ]; then
    echo "Error: Image file too small (< $HEADER_SIZE bytes)" >&2
    exit 1
fi

echo "Reading .nvpfwimage: $IMAGE"

# Create a temporary directory for processing
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Extract first 88 bytes of the header for parsing
dd if="$IMAGE" bs=1 count=88 of="$TMPDIR/header_struct.bin" 2>/dev/null

# Parse header using python3 (most reliable for struct unpack in a shell script)
# HEADER_STRUCT = struct.Struct("<IIIB72s") -> I (magic), I (payload_len), I (crc32), B (sig_len), 72s (sig_padded)
PARSED_HEADER=$(python3 -c "
import struct, sys
with open('$TMPDIR/header_struct.bin', 'rb') as f:
    data = f.read(88)
    magic, payload_len, crc32_stored, sig_len, sig_padded = struct.unpack('<IIIB72s', data[:85])
    print(f'{magic} {payload_len} {crc32_stored} {sig_len}')
    # Write signature to file
    with open('$TMPDIR/signature.bin', 'wb') as s:
        s.write(sig_padded[:sig_len])
")

read -r MAGIC_GOT PAYLOAD_LEN CRC32_STORED SIG_LEN <<< "$PARSED_HEADER"

# Verify Magic
if [ "$MAGIC_GOT" -ne "$((MAGIC))" ]; then
    printf "Error: Invalid magic number. Expected 0x%08x, got 0x%08x\n" "$MAGIC" "$MAGIC_GOT" >&2
    exit 1
fi
echo "Magic: OK"

# Check payload length
REQUIRED_SIZE=$((HEADER_SIZE + PAYLOAD_LEN))
if [ "$FILE_SIZE" -lt "$REQUIRED_SIZE" ]; then
    echo "Error: Image file too small for declared payload ($PAYLOAD_LEN bytes)" >&2
    exit 1
fi

# Extract payload
dd if="$IMAGE" bs=1 skip="$HEADER_SIZE" count="$PAYLOAD_LEN" of="$TMPDIR/payload.bin" 2>/dev/null
echo "Payload size: $PAYLOAD_LEN bytes"

# Verify CRC32
echo "Verifying CRC32..."
CRC32_COMPUTED=$(python3 -c "import binascii; print(binascii.crc32(open('$TMPDIR/payload.bin', 'rb').read()) & 0xFFFFFFFF)")

if [ "$CRC32_COMPUTED" -ne "$CRC32_STORED" ]; then
    printf "Error: CRC32 mismatch. Expected 0x%08x, got 0x%08x\n" "$CRC32_STORED" "$CRC32_COMPUTED" >&2
    exit 1
fi
echo "CRC32: OK"

# Check signature presence
if [ "$SIG_LEN" -eq 0 ]; then
    echo "Error: No signature found in image (sig_length = 0)" >&2
    exit 1
fi

if [ "$SIG_LEN" -lt "$MIN_SIGNATURE_SIZE" ] || [ "$SIG_LEN" -gt "$MAX_SIGNATURE_SIZE" ]; then
    echo "Error: Invalid signature length $SIG_LEN (expected $MIN_SIGNATURE_SIZE-$MAX_SIGNATURE_SIZE)" >&2
    exit 1
fi
echo "Signature size: $SIG_LEN bytes"

# Verify ECDSA-SHA256 signature
echo "Verifying ECDSA-SHA256 signature..."
# Note: openssl dgst -verify requires the public key in PEM format.
if $OPENSSL_BIN dgst -sha256 -verify "$PUBLIC_KEY" -signature "$TMPDIR/signature.bin" "$TMPDIR/payload.bin" > /dev/null 2>&1; then
    echo "Signature verification successful ✓"
    exit 0
else
    echo "Error: Signature verification failed (invalid signature)" >&2
    exit 1
fi

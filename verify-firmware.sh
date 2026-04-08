#!/usr/bin/env bash

# ─────────────────────────────────────────────────────────────────
#  VERIFY-FIRMWARE.SH
#  Verifies firmware signature and CRC32 in a .nvpfwimage file.
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

# Dependencies check
if ! command -v crc32 &> /dev/null; then
    echo "Error: 'crc32' utility not found." >&2
    echo "On macOS, it is usually pre-installed. On Linux, install 'libarchive-zip-perl'." >&2
    exit 1
fi

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
OPENSSL_BIN="${OPENSSL_BIN-openssl}"

# Header configuration
MAGIC_EXPECTED="242666a0"
HEADER_SIZE=2048

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

if [[ ! -f "$IMAGE" || ! -f "$PUBLIC_KEY" ]]; then
    echo "Error: Image or Public Key file not found." >&2
    exit 1
fi

echo "Verifying .nvpfwimage: $IMAGE"

# Create a temporary directory for processing
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Magic (4 bytes), Payload Len (4 bytes), CRC32 Stored (4 bytes), Sig Len (1 byte)
MAGIC_GOT=$(od -An -N4 -t x4 < "$IMAGE" | xargs)
PAYLOAD_LEN=$(od -An -j4 -N4 -t u4 < "$IMAGE" | xargs)
CRC32_STORED=$(od -An -j8 -N4 -t x4 < "$IMAGE" | xargs | tr -d ' ')
SIG_LEN=$(od -An -j12 -N1 -t u1 < "$IMAGE" | xargs)

# Verify Magic
if [[ "$MAGIC_GOT" != "$MAGIC_EXPECTED" ]]; then
    printf "Error: Invalid magic number. Expected 0x%s, got 0x%s\n" "$MAGIC_EXPECTED" "$MAGIC_GOT" >&2
    exit 1
fi

# Extract signature and payload
dd if="$IMAGE" bs=1 skip=13 count="$SIG_LEN" of="$TMPDIR/sig.bin" 2>/dev/null
dd if="$IMAGE" bs=1 skip="$HEADER_SIZE" count="$PAYLOAD_LEN" of="$TMPDIR/payload.bin" 2>/dev/null

# Verify CRC32
CRC32_COMPUTED=$(crc32 "$TMPDIR/payload.bin" | tr -d ' ')
if [[ "${CRC32_COMPUTED#0x}" != "${CRC32_STORED#0x}" ]]; then
    printf "Error: CRC32 mismatch. Expected 0x%s, got 0x%s\n" "$CRC32_STORED" "$CRC32_COMPUTED" >&2
    exit 1
fi
echo "CRC32: OK"

# Verify ECDSA-SHA256 signature
echo "Verifying signature..."
if "$OPENSSL_BIN" dgst -sha256 -verify "$PUBLIC_KEY" -signature "$TMPDIR/sig.bin" "$TMPDIR/payload.bin" > /dev/null 2>&1; then
    echo "Signature verification successful !"
    exit 0
else
    echo "Error: Signature verification failed: invalid key !" >&2
    exit 1
fi

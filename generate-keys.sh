#!/bin/bash

# ─────────────────────────────────────────────────────────────────
#  GENERATE-KEYS.SH
#  Generates a pair of ECDSA (P-256) keys in PEM format.
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

PRIVATE_KEY="private_key.pem"
PUBLIC_KEY="public_key.pem"
OPENSSL_BIN="${OPENSSL_BIN-openssl}"

# ─────────────────────────────────────────────────────────────────

if [ -e "$PRIVATE_KEY" ]; then
    echo "Refusing to overwrite existing file: $PRIVATE_KEY." >&2
    exit 1
fi

if [ -e "$PUBLIC_KEY" ]; then
    echo "Refusing to overwrite existing file: $PUBLIC_KEY." >&2
    exit 1
fi

umask 077

echo "Generating ECDSA (SECP256R1) private key..."
"$OPENSSL_BIN" genpkey \
    -algorithm EC \
    -pkeyopt ec_paramgen_curve:P-256 \
    -out "$PRIVATE_KEY"

echo "Extracting public key..."
"$OPENSSL_BIN" pkey \
    -in "$PRIVATE_KEY" \
    -pubout \
    -out "$PUBLIC_KEY"

echo ""
echo "Keys generated successfully:"
echo "  - Private: $PRIVATE_KEY"
echo "  - Public:  $PUBLIC_KEY"
echo ""
echo "Note: You can convert these to DER format using pem-to-der.sh"

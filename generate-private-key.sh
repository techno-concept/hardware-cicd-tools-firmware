#!/bin/bash

set -euo pipefail

# ─────────────────────────────────────────────────────────────────
# CONFIGURATION - EDIT BEFORE RUNNING
# ─────────────────────────────────────────────────────────────────
PRIVATE_KEY="private_key.der"
# ─────────────────────────────────────────────────────────────────

if [ -e "$PRIVATE_KEY" ]; then
    echo "Refusing to overwrite existing file: $PRIVATE_KEY." >&2
    exit 1
fi

umask 077

echo "Generating ECDSA (SECP256R1) private key in DER format..."

OPENSSL_BIN="${OPENSSL_BIN-openssl}"

"$OPENSSL_BIN" genpkey \
    -algorithm EC \
    -pkeyopt ec_paramgen_curve:P-256 | \
    "$OPENSSL_BIN" pkey \
        -outform DER \
        -out "$PRIVATE_KEY" && \
    "$OPENSSL_BIN" pkcs8 \
        -inform DER \
        -in private_key.der \
        -nocrypt \
        -out /dev/null

echo "Private key generated: $PRIVATE_KEY."

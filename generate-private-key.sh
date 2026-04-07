#!/bin/bash

set -euo pipefail

PRIVATE_KEY="${1:-private_key.der}"

if [ -z "${1:-}" ]; then
    echo "[i] No output file specified. Using default: $PRIVATE_KEY"
    echo "[i] Tip: you can pass a filename as the first argument"
fi

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

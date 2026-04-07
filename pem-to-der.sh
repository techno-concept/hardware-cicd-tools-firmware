#!/bin/bash

# ─────────────────────────────────────────────────────────────────
#  PEM-TO-DER.SH
#  Converts a PEM key (private or public) to DER format.
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

INPUT_PEM="private_key.pem"
OUTPUT_DER="private_key.der"
OPENSSL_BIN="${OPENSSL_BIN-openssl}"

if [ ! -f "$INPUT_PEM" ]; then
    echo "Error: Input file '$INPUT_PEM' not found." >&2
    exit 1
fi

if [ -e "$OUTPUT_DER" ]; then
    echo "Refusing to overwrite existing file: $OUTPUT_DER." >&2
    exit 1
fi

echo "Converting $INPUT_PEM to $OUTPUT_DER..."

"$OPENSSL_BIN" pkcs8 \
    -topk8 \
    -nocrypt \
    -in $INPUT_PEM \
    -outform DER \
    -out "$OUTPUT_DER"

# validate
"$OPENSSL_BIN" pkcs8 \
    -inform DER \
    -in "$OUTPUT_DER" \
    -nocrypt \
    -out /dev/null

echo "Conversion complete."

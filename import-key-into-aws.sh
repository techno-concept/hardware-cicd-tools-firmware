#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AWS_PROFILE:-bruxless-admin}"
REGION="${AWS_REGION:-eu-west-3}"
KEY_DER="${1:-private_key.der}"

if [ ! -f "$KEY_DER" ]; then
  echo "[!] Missing private key: $KEY_DER" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# create empty key
KEY_ID="$(
  aws kms create-key \
    --profile "$PROFILE" \
    --region "$REGION" \
    --origin EXTERNAL \
    --key-spec ECC_NIST_P256 \
    --key-usage SIGN_VERIFY \
    --query 'KeyMetadata.KeyId' \
    --output text
)"

# get wrapping key + token to cipher private key during transport
aws kms get-parameters-for-import \
  --profile "$PROFILE" \
  --region "$REGION" \
  --key-id "$KEY_ID" \
  --wrapping-algorithm RSAES_OAEP_SHA_256 \
  --wrapping-key-spec RSA_4096 \
  --output json > "$TMPDIR/import.json"

jq -r '.PublicKey' "$TMPDIR/import.json" | base64 --decode > "$TMPDIR/wrapping_key.der"
jq -r '.ImportToken' "$TMPDIR/import.json" | base64 --decode > "$TMPDIR/import_token.bin"

OPENSSL_BIN="${OPENSSL_BIN-openssl}"

# convert wrapping public key DER -> PEM (better portability)
"$OPENSSL_BIN" pkey \
  -pubin \
  -inform DER \
  -in "$TMPDIR/wrapping_key.der" \
  -outform PEM \
  -out "$TMPDIR/wrapping_key.pem"

# cipher private key
"$OPENSSL_BIN" pkeyutl \
  -encrypt \
  -pubin \
  -inkey "$TMPDIR/wrapping_key.pem" \
  -keyform PEM \
  -in "$KEY_DER" \
  -out "$TMPDIR/encrypted_key_material.bin" \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256 \
  -pkeyopt rsa_mgf1_md:sha256

# import key
aws kms import-key-material \
  --profile "$PROFILE" \
  --region "$REGION" \
  --key-id "$KEY_ID" \
  --encrypted-key-material "fileb://$TMPDIR/encrypted_key_material.bin" \
  --import-token "fileb://$TMPDIR/import_token.bin" \
  --expiration-model KEY_MATERIAL_DOES_NOT_EXPIRE

echo "Imported key into KMS:"
echo "Imported key: $KEY_ID"

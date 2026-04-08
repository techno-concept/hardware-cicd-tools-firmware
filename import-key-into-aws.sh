#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────
# CONFIGURATION - EDIT BEFORE RUNNING
# ─────────────────────────────────────────────────────────────────
PROFILE="${AWS_PROFILE:-bruxless-admin}"
REGION="${AWS_REGION:-eu-west-3}"
KEY_DER="private_key.der"

# NOTE: This alias must be exactly the same as the one configured in create-or-update-github-signer.sh
KMS_ALIAS="alias/sec/firmware-signer"

# Names for the policy principals
ROLE_NAME="githubSigner"
KMS_ADMIN_USER="kms-provisioner-firmware-crossover"
# ─────────────────────────────────────────────────────────────────

if [ ! -f "$KEY_DER" ]; then
  echo "[!] Missing private key: $KEY_DER" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "[...] Fetching AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" --query "Account" --output text)
echo "[OK] Account ID: $ACCOUNT_ID"

# Create the Key Policy (KMS Key Policy, not an IAM Trust Policy)
KEY_POLICY_FILE="$TMPDIR/key-policy.json"
cat > "$KEY_POLICY_FILE" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnableRootPermissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowKeyAdmin",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:user/${KMS_ADMIN_USER}"
      },
      "Action": [
        "kms:PutKeyPolicy",
        "kms:UpdateKeyDescription",
        "kms:EnableKey",
        "kms:DisableKey",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowGitHubSignerUseKey",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
      },
      "Action": [
        "kms:Sign",
        "kms:GetPublicKey",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
EOF

echo "[...] Creating KMS key with dynamic policy..."
# create empty key
KEY_ID="$(
  aws kms create-key \
    --profile "$PROFILE" \
    --region "$REGION" \
    --origin EXTERNAL \
    --key-spec ECC_NIST_P256 \
    --key-usage SIGN_VERIFY \
    --policy "file://$KEY_POLICY_FILE" \
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

if [ -n "$KMS_ALIAS" ]; then
  # Check if alias already exists to update it, or create a new one
  ALIAS_EXISTS=$(aws kms list-aliases --profile "$PROFILE" --region "$REGION" --query "Aliases[?AliasName=='${KMS_ALIAS}'].AliasName" --output text)
  if [ -n "$ALIAS_EXISTS" ] && [ "$ALIAS_EXISTS" != "None" ]; then
    echo "Updating existing alias $KMS_ALIAS to point to $KEY_ID..."
    aws kms update-alias --profile "$PROFILE" --region "$REGION" --alias-name "$KMS_ALIAS" --target-key-id "$KEY_ID"
  else
    echo "Creating alias $KMS_ALIAS for $KEY_ID..."
    aws kms create-alias --profile "$PROFILE" --region "$REGION" --alias-name "$KMS_ALIAS" --target-key-id "$KEY_ID"
  fi
  echo "Alias ready: $KMS_ALIAS"
fi

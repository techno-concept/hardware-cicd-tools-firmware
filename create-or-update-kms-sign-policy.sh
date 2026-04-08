#!/usr/bin/env bash
# =============================================================================
# create-or-update-kms-sign-policy.sh
# =============================================================================
# Manage the IAM managed policy AllowBruxlessKmsSign for KMS signing.
# Uses kms:RequestAlias to avoid pinning to a specific Key ID or ARN.
# =============================================================================
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-bruxless-admin}"
export AWS_PROFILE
REGION="${AWS_REGION:-eu-west-3}"

IAM_POLICY_NAME="AllowBruxlessKmsSign"
ROLE_NAME="githubSigner"
KMS_ALIAS="alias/sec/firmware-signer"

echo "═══════════════════════════════════════════════════════════════"
echo "  $(basename "$0")"
echo "═══════════════════════════════════════════════════════════════"

ACCOUNT_ID=$(aws sts get-caller-identity --region "$REGION" --query "Account" --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${IAM_POLICY_NAME}"

POLICY_DOC=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowKmsSignViaAlias",
    "Effect": "Allow",
    "Action": ["kms:Sign", "kms:GetPublicKey", "kms:DescribeKey"],
    "Resource": "*",
    "Condition": {
      "StringEquals": {
        "kms:RequestAlias": "${KMS_ALIAS}"
      }
    }
  }]
}
EOF
)

echo "[...] Creating policy if not exists..."

CREATE_OUTPUT=$(aws iam create-policy \
  --policy-name "$IAM_POLICY_NAME" \
  --description "Allow firmware signing via KMS alias ${KMS_ALIAS}" \
  --policy-document "$POLICY_DOC" \
  --query "Policy.Arn" \
  --output text 2>&1 || true)

if echo "$CREATE_OUTPUT" | grep -q "arn:aws:iam::"; then
  echo "[OK] Policy created: $CREATE_OUTPUT"
  exit 0
fi

if ! echo "$CREATE_OUTPUT" | grep -q "EntityAlreadyExists"; then
  echo "[!] Unexpected error:"
  echo "$CREATE_OUTPUT"
  exit 1
fi

echo "[...] Policy exists → replacing"

echo "[...] Detaching from role (if attached)..."
aws iam detach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "$POLICY_ARN" >/dev/null 2>&1 || true

echo "[...] Deleting non-default versions..."
aws iam list-policy-versions \
  --policy-arn "$POLICY_ARN" \
  --output json |
jq -r '.Versions[] | select(.IsDefaultVersion == false) | .VersionId' |
while read -r v; do
  [ -z "$v" ] && continue
  aws iam delete-policy-version \
    --policy-arn "$POLICY_ARN" \
    --version-id "$v"
done

echo "[...] Deleting policy..."
aws iam delete-policy --policy-arn "$POLICY_ARN"

echo "[...] Recreating policy..."
aws iam create-policy \
  --policy-name "$IAM_POLICY_NAME" \
  --description "Allow firmware signing via KMS alias ${KMS_ALIAS}" \
  --policy-document "$POLICY_DOC" >/dev/null

echo "[OK] Policy replaced: $POLICY_ARN"

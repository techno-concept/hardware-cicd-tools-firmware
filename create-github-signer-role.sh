#!/usr/bin/env bash
# =============================================================================
# create-github-signer-role.sh
# =============================================================================
# Configure AWS policy & IAM role to sign firmware via KMS.
#
# Prerequisite: The KMS key must already exist. You can create it with:
# ./import-key-into-aws.sh private_key.der alias/sec/firmware-signer
#
# This script will read the AWS_PROFILE and AWS_REGION.
# Edit the variables below to tailor the IAM policy and roles to your needs.
# =============================================================================
set -euo pipefail

# ─────────────────────────────────────────────────────────────────
# CONFIGURATION - EDIT BEFORE RUNNING
# ─────────────────────────────────────────────────────────────────
AWS_PROFILE="${AWS_PROFILE:-bruxless-admin}"
export AWS_PROFILE
REGION="${AWS_REGION:-eu-west-3}"

# The alias of the KMS key created during the import process.
# NOTE: This alias must be exactly the same as the one configured in import-key-into-aws.sh
KMS_ALIAS="alias/sec/firmware-signer"

# Name of the IAM Role and Policy to create
ROLE_NAME="githubSigner"
IAM_POLICY_NAME="AllowBruxlessKmsSign"

# List of trusted GitHub respositories formatted as:
# repo:OrgName/RepoName:ref:refs/heads/BranchName
GITHUB_REPOS=(
  "repo:TechnoConcept/cross-technoconcept-bruxless-qa:ref:refs/heads/main"
  "repo:TechnoConcept/hardware-cicd-tools-firmware:ref:refs/heads/main"
)

# List of developer IAM ARNs that are allowed to assume this role for local signing
# Format: "arn:aws:iam::123456789012:user/firstname.lastname"
DEVELOPER_ARNS=(
  # "arn:aws:iam::123456789012:user/thierry"
)

echo "═══════════════════════════════════════════════════════════════"
echo "  create-github-signer-role.sh"
echo "  AWS Profile: $AWS_PROFILE | Region: $REGION"
echo "═══════════════════════════════════════════════════════════════"

echo ""
echo "─── [1/4] Identity extraction ──────────────────────────────────"
CALLER_IDENTITY=$(aws sts get-caller-identity --region "$REGION" --output json)
ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
ADMIN_ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')
echo "[OK] AWS Account : $ACCOUNT_ID"

echo ""
echo "─── [2/4] Resolving KMS Key from Alias ────────────────────────"
KEY_ID=$(aws kms describe-key \
  --key-id "$KMS_ALIAS" \
  --region "$REGION" \
  --query "KeyMetadata.KeyId" \
  --output text 2>/dev/null || true)

if [ -z "$KEY_ID" ] || [ "$KEY_ID" == "None" ]; then
  echo "[!] Could not resolve KMS key for alias $KMS_ALIAS"
  echo "    Did you run ./import-key-into-aws.sh ?"
  exit 1
fi
echo "[OK] Resolved alias $KMS_ALIAS to Key ID: $KEY_ID"
KMS_KEY_ARN="arn:aws:kms:${REGION}:${ACCOUNT_ID}:key/${KEY_ID}"

echo ""
echo "─── [3/4] IAM Policy ($IAM_POLICY_NAME) ───────────────────────"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${IAM_POLICY_NAME}"

POLICY_DOC=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Sid": "AllowKmsSign",
        "Effect": "Allow",
        "Action": ["kms:Sign", "kms:GetPublicKey", "kms:DescribeKey"],
        "Resource": "$KMS_KEY_ARN"
    }]
}
EOF
)

# Attempt to create or update policy
if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
    echo "[...] Policy exists. Updating default version..."
    aws iam create-policy-version \
        --policy-arn "$POLICY_ARN" \
        --policy-document "$POLICY_DOC" \
        --set-as-default >/dev/null 2>&1 || {
            echo "[!] Could not create a new version (perhaps maximum versions reached)."
            echo "    Please cleanup old versions via AWS Console, or ignore if unchanged."
        }
    echo "[OK] Policy updated: $POLICY_ARN"
else
    echo "[...] Creating policy..."
    CREATE_OUTPUT=$(aws iam create-policy \
        --policy-name "$IAM_POLICY_NAME" \
        --description "Allow firmware signing via KMS" \
        --policy-document "$POLICY_DOC" \
        --query "Policy.Arn" \
        --output text)
    POLICY_ARN="$CREATE_OUTPUT"
    echo "[OK] Policy created: $POLICY_ARN"
fi

echo ""
echo "─── [4/4] Setup IAM Role ($ROLE_NAME) ─────────────────────────"

# 1. GitHub OIDC Provider Check
OIDC_THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"
GITHUB_OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$GITHUB_OIDC_ARN" > /dev/null 2>&1; then
    echo "[...] Creating GitHub OIDC Provider..."
    aws iam create-open-id-connect-provider \
        --url "https://token.actions.githubusercontent.com" \
        --client-id-list "sts.amazonaws.com" \
        --thumbprint-list "$OIDC_THUMBPRINT" > /dev/null
    echo "[OK] GitHub OIDC Provider created."
fi

# 2. Build Trust Policy Document dynamically
# Convert GitHub Repos to JSON Array string
GH_REPOS_JSON=$(printf '%s\n' "${GITHUB_REPOS[@]}" | jq -R . | jq -s .)

# Convert Dev ARNs to JSON Array string. We always include the admin to avoid empty arrays which AWS rejects.
DEV_ARNS_JSON=$(printf '%s\n' "${DEVELOPER_ARNS[@]}" "$ADMIN_ARN" | sort -u | jq -R . | jq -s .)

TRUST_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "GitHubActionsOIDC",
            "Effect": "Allow",
            "Principal": { "Federated": "$GITHUB_OIDC_ARN" },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": $GH_REPOS_JSON
                }
            }
        },
        {
            "Sid": "AdminLocalAssume",
            "Effect": "Allow",
            "Principal": { "AWS": $DEV_ARNS_JSON },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)

ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text 2>/dev/null || true)

if [ -n "$ROLE_ARN" ]; then
    echo "[OK] Role exists — updating Trust Policy..."
    aws iam update-assume-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-document "$TRUST_POLICY"
else
    echo "[...] Creating Role $ROLE_NAME..."
    ROLE_ARN=$(aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "Firmware Signing: GitHub Actions (OIDC) + local developers" \
        --query "Role.Arn" \
        --output text)
    echo "[OK] Role created: $ROLE_ARN"
fi

aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" 2>/dev/null || true
echo "[OK] Policy $IAM_POLICY_NAME attached to Role $ROLE_NAME"

echo ""
echo "✅ Role ready. Role ARN: $ROLE_ARN"

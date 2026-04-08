#!/usr/bin/env bash
# =============================================================================
# create-or-update-github-signer-role.sh
# =============================================================================
# Manage the IAM Role githubSigner and its trust relationship with GitHub.
# Attaches the AllowBruxlessKmsSign managed policy.
# =============================================================================
set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-bruxless-admin}"
export AWS_PROFILE
REGION="${AWS_REGION:-eu-west-3}"

ROLE_NAME="githubSigner"
IAM_POLICY_NAME="AllowBruxlessKmsSign"

GITHUB_REPOS=(
  "repo:techno-concept/bruxless-headset-firmware:*"
)

echo "═══════════════════════════════════════════════════════════════"
echo "  $(basename "$0")"
echo "  AWS Profile: $AWS_PROFILE | Region: $REGION"
echo "═══════════════════════════════════════════════════════════════"

ACCOUNT_ID=$(aws sts get-caller-identity --region "$REGION" --query "Account" --output text)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${IAM_POLICY_NAME}"
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

echo ""
echo "─── [1/3] OIDC Provider ───────────────────────────────────────"

if aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  echo "[OK] GitHub OIDC Provider already exists."
else
  echo "[...] Creating GitHub OIDC Provider..."
  aws iam create-open-id-connect-provider \
    --url "https://token.actions.githubusercontent.com" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" >/dev/null
  echo "[OK] GitHub OIDC Provider created."
fi

echo ""
echo "─── [2/3] IAM Role ($ROLE_NAME) ───────────────────────────────"

GH_REPOS_JSON=$(printf '%s\n' "${GITHUB_REPOS[@]}" | jq -R . | jq -s .)

TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GitHubActionsOIDC",
      "Effect": "Allow",
      "Principal": { "Federated": "$OIDC_ARN" },
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
      "Sid": "DelegationCompteAWS",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::${ACCOUNT_ID}:root" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "[...] Role exists → updating trust policy..."
  aws iam update-assume-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-document "$TRUST_POLICY"
  echo "[OK] Trust policy updated."
else
  echo "[...] Creating role $ROLE_NAME..."
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" \
    --description "Firmware Signing: GitHub Actions (OIDC) + local developers" \
    >/dev/null
  echo "[OK] Role created: $ROLE_ARN"
fi

echo ""
echo "─── [3/3] Policy Attachment ───────────────────────────────────"

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "$POLICY_ARN" >/dev/null

echo "[OK] Policy attached: $IAM_POLICY_NAME"
echo "[OK] Role ready: $ROLE_ARN"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  HOW TO AUTHORIZE A LOCAL DEVELOPER ?"
echo "═══════════════════════════════════════════════════════════════"
echo "You have to add this IAM policy to the user of the developer on AWS-side:"
echo ""
echo "{"
echo "  \"Version\": \"2012-10-17\","
echo "  \"Statement\": ["
echo "    {"
echo "      \"Sid\": \"AllowAssumeGithubSignerRole\","
echo "      \"Effect\": \"Allow\","
echo "      \"Action\": \"sts:AssumeRole\","
echo "      \"Resource\": \"$ROLE_ARN\""
echo "    }"
echo "  ]"
echo "}"
echo "═══════════════════════════════════════════════════════════════"

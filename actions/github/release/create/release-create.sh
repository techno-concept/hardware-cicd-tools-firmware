#!/bin/bash

# Parameters
DRAFT=$1
PRERELEASE=$2

# Convert the string input to a proper boolean
if [ "$DRAFT" == "true" ]; then
  DRAFT_BOOL=true
else
  DRAFT_BOOL=false
fi
if [ "$PRERELEASE" == "true" ]; then
  PRERELEASE_BOOL=true
else
  PRERELEASE_BOOL=false
fi

# Set the GitHub API URL
API_URL="$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/releases"

# Make the API call with curl
RESPONSE=$(curl -s -w "%{http_code}" -o temp.txt -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/json" \
  $API_URL \
  -d '{
        "draft": '$DRAFT_BOOL',
        "generate_release_notes": 'false',
        "name": "'$RELEASE_TAG'",
        "tag_name": "'$TAG_NAME'",
        "draft": '$DRAFT_BOOL'
      }')

# Check for a successful response and parse needed data
if [ "$(echo "$RESPONSE" | jq -r '.id')" != null ]; then
  # Parse variables
  RELEASE_ID=$(echo "$RESPONSE" | jq -r '.id')
  RELEASE_HTML_URL=$(echo "$RESPONSE" | jq -r '.html_url')
  RELEASE_UPLOAD_URL=$(echo "$RESPONSE" | jq -r '.upload_url')

  # Set outputs for GitHub Actions
  echo "::set-output name=RELEASE_ID::$RELEASE_ID"
  echo "::set-output name=RELEASE_HTML_URL::$RELEASE_HTML_URL"
  echo "::set-output name=RELEASE_UPLOAD_URL::$RELEASE_UPLOAD_URL"

  echo "Release created successfully: ID $RELEASE_ID, URL $RELEASE_HTML_URL, UPLOAD URL $RELEASE_UPLOAD_URL"
else
  echo "Failed to create release"
  echo "Response: $RESPONSE"
  exit 1
fi
#!/bin/bash

echo "🧪 Testing Tekton Pipeline Webhook..."
echo ""

# Get current git information dynamically
GIT_REMOTE_RAW=$(git remote get-url origin)
# Clean URL by removing credentials if present
GIT_REMOTE_URL=$(echo "$GIT_REMOTE_RAW" | sed 's/https:\/\/.*@/https:\/\//')
REPO_NAME=$(basename "$GIT_REMOTE_URL" .git)
CURRENT_SHA=$(git rev-parse HEAD)
SHORT_SHA=$(git rev-parse --short HEAD)
CURRENT_BRANCH=$(git branch --show-current)

echo "📋 Repository Information:"
echo "   Clone URL: $GIT_REMOTE_URL"
echo "   Repository Name: $REPO_NAME"
echo "   Current SHA: $CURRENT_SHA"
echo "   Short SHA: $SHORT_SHA"
echo "   Current Branch: $CURRENT_BRANCH"
echo ""

# Construct webhook payload dynamically
WEBHOOK_URL="http://webhook.10.34.2.129.nip.io"

PAYLOAD=$(jq -n \
  --arg clone_url "$GIT_REMOTE_URL" \
  --arg repo_name "$REPO_NAME" \
  --arg after "$CURRENT_SHA" \
  --arg short_sha "$SHORT_SHA" \
  --arg ref "refs/heads/$CURRENT_BRANCH" \
  '{
    "repository": {
      "clone_url": $clone_url,
      "name": $repo_name
    },
    "after": $after,
    "short_sha": $short_sha,
    "ref": $ref
  }')

echo "🚀 Sending webhook request to: $WEBHOOK_URL"
echo "📦 Payload:"
echo "$PAYLOAD" | jq '.'
echo ""

# Send the webhook request
echo "📡 Sending request..."
RESPONSE=$(curl -w "\nHTTP_CODE:%{http_code}" -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -d "$PAYLOAD" 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
RESPONSE_BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

echo "📊 Response (HTTP $HTTP_CODE):"
echo "$RESPONSE_BODY"
echo ""

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo "✅ Webhook triggered successfully!"
  echo ""
  echo "🔍 Expected PipelineRun name: pytest-run-$SHORT_SHA"
  echo ""
  echo "🌐 Check these links:"
  echo "   📊 Tekton Dashboard: http://tekton.10.34.2.129.nip.io"
  echo "   🎯 PipelineRun: http://tekton.10.34.2.129.nip.io/#/namespaces/tekton-pipelines/pipelineruns/pytest-run-$SHORT_SHA"
  echo "   📈 Artifacts: http://artifacts.10.34.2.129.nip.io/pytest-run-$SHORT_SHA/"
  echo ""
  echo "⏱️  Wait ~30 seconds then check for the new PipelineRun:"
  echo "   kubectl get pipelinerun pytest-run-$SHORT_SHA -n tekton-pipelines"
else
  echo "❌ Webhook request failed (HTTP $HTTP_CODE)"
  echo "Response: $RESPONSE_BODY"
  exit 1
fi

#!/usr/bin/env bash
# Automated Vercel deployment for credila-app-V2 — no CLI, no Node, just curl.
#
# Usage:
#   VERCEL_TOKEN=xxxxx ./deploy.sh
#   # or save the token once to a gitignored file:
#   echo "xxxxx" > .vercel-token && ./deploy.sh
#
# Optional env: VERCEL_PROJECT (default credila-app-v2), VERCEL_TEAM_ID
set -euo pipefail
cd "$(dirname "$0")"

# --- Resolve token (env var wins, else .vercel-token file) ---
if [ -z "${VERCEL_TOKEN:-}" ] && [ -f .vercel-token ]; then
  VERCEL_TOKEN="$(tr -d '[:space:]' < .vercel-token)"
fi
: "${VERCEL_TOKEN:?Provide a Vercel token via VERCEL_TOKEN env var or a .vercel-token file}"

PROJECT="${VERCEL_PROJECT:-credila-app-v2}"
API="https://api.vercel.com"
AUTH="Authorization: Bearer ${VERCEL_TOKEN}"
TEAM_QS=""
if [ -n "${VERCEL_TEAM_ID:-}" ]; then TEAM_QS="?teamId=${VERCEL_TEAM_ID}"; fi

FILES=(index.html vercel.json)

echo "→ Uploading files to Vercel..."
files_json=""
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "  ✗ missing $f"; exit 1; }
  sha=$(shasum -a 1 "$f" | awk '{print $1}')
  size=$(wc -c < "$f" | tr -d ' ')
  http=$(curl -s -o /tmp/vercel_upload.json -w '%{http_code}' -X POST "${API}/v2/files${TEAM_QS}" \
    -H "$AUTH" -H "Content-Type: application/octet-stream" -H "x-vercel-digest: ${sha}" \
    --data-binary "@${f}")
  if [ "$http" != "200" ] && [ "$http" != "201" ]; then
    echo "  ✗ upload failed for $f (HTTP $http):"; cat /tmp/vercel_upload.json; echo; exit 1
  fi
  echo "  ✓ $f (${size} bytes, sha ${sha:0:8})"
  files_json="${files_json}{\"file\":\"${f}\",\"sha\":\"${sha}\",\"size\":${size}},"
done
files_json="[${files_json%,}]"

echo "→ Creating production deployment..."
payload="{\"name\":\"${PROJECT}\",\"files\":${files_json},\"target\":\"production\",\"projectSettings\":{\"framework\":null}}"
http=$(curl -s -o /tmp/vercel_deploy.json -w '%{http_code}' -X POST "${API}/v13/deployments${TEAM_QS}" \
  -H "$AUTH" -H "Content-Type: application/json" -d "$payload")
if [ "$http" != "200" ] && [ "$http" != "201" ]; then
  echo "  ✗ deployment failed (HTTP $http):"; cat /tmp/vercel_deploy.json; echo; exit 1
fi

url=$(grep -o '"url":"[^"]*"' /tmp/vercel_deploy.json | head -1 | cut -d'"' -f4)
echo ""
echo "✅ Deployment created: https://${url}"
echo "   (production alias is assigned once the build finishes)"

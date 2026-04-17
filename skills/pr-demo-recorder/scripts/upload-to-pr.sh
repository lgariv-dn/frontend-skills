#!/usr/bin/env bash
# Upload a demo video/image to the current PR's head branch and prepend an
# embed to the PR description. Preserves existing body content (never
# overwrites screenshots/images already posted).
#
# Usage: upload-to-pr.sh <local-file> [remote-path]
#   local-file   Path to the MP4/GIF/WebM/PNG to upload.
#   remote-path  Optional. Defaults to docs/pr-assets/<basename>.

set -euo pipefail

LOCAL="${1:?Usage: upload-to-pr.sh <local-file> [remote-path]}"
REMOTE="${2:-docs/pr-assets/$(basename "$LOCAL")}"

if [[ ! -f "$LOCAL" ]]; then
  echo "File not found: $LOCAL" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "jq not installed" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "gh CLI not installed" >&2; exit 1; }

# Resolve PR + repo metadata (fails if no PR open on current branch)
PR_NUMBER=$(gh pr view --json number -q .number)
BRANCH=$(gh pr view --json headRefName -q .headRefName)
OWNER=$(gh repo view --json owner -q .owner.login)
REPO=$(gh repo view --json name -q .name)

echo "Target: PR #${PR_NUMBER} on ${OWNER}/${REPO} (branch: ${BRANCH})"
echo "Uploading ${LOCAL} → ${REMOTE}"

# Base64-encode the file for the Contents API
B64=$(base64 < "$LOCAL" | tr -d '\n')

# If the file already exists at that path on that branch, we need its SHA to overwrite
EXISTING_SHA=$(gh api "/repos/$OWNER/$REPO/contents/$REMOTE?ref=$BRANCH" 2>/dev/null | jq -r '.sha // empty' 2>/dev/null || true)

# Build JSON payload (avoids command-line length limits with large base64 blobs)
PAYLOAD=$(mktemp)
trap 'rm -f "$PAYLOAD" "${PAYLOAD}.new" "${BODY_FILE:-}"' EXIT

jq -n \
  --arg message "Add PR demo asset: $(basename "$LOCAL")" \
  --arg content "$B64" \
  --arg branch "$BRANCH" \
  '{message: $message, content: $content, branch: $branch}' > "$PAYLOAD"

if [[ -n "$EXISTING_SHA" ]]; then
  jq --arg sha "$EXISTING_SHA" '. + {sha: $sha}' "$PAYLOAD" > "${PAYLOAD}.new"
  mv "${PAYLOAD}.new" "$PAYLOAD"
fi

gh api -X PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/$OWNER/$REPO/contents/$REMOTE" \
  --input "$PAYLOAD" >/dev/null

echo "  ✓ uploaded to $BRANCH"

# Build the embed snippet based on file type
RAW_URL="https://github.com/$OWNER/$REPO/blob/$BRANCH/$REMOTE?raw=true"
EXT="${LOCAL##*.}"
case "${EXT,,}" in
  mp4|webm|mov) EMBED="<video src=\"$RAW_URL\" controls width=\"720\"></video>" ;;
  gif|png|jpg|jpeg) EMBED="![demo]($RAW_URL)" ;;
  *) EMBED="[Demo]($RAW_URL)" ;;
esac

# Prepend embed to existing PR body (preserves everything that was already there)
EXISTING_BODY=$(gh pr view "$PR_NUMBER" --json body -q .body)
BODY_FILE=$(mktemp)

# Skip if the embed URL is already in the body (idempotent re-runs)
if grep -qF "$RAW_URL" <<< "$EXISTING_BODY"; then
  echo "  ⚠ embed already present in PR body; skipping body edit"
else
  printf '%s\n\n%s\n' "$EMBED" "$EXISTING_BODY" > "$BODY_FILE"
  gh pr edit "$PR_NUMBER" --body-file "$BODY_FILE"
  echo "  ✓ PR #${PR_NUMBER} body updated (embed prepended)"
fi

echo ""
echo "Embed URL: $RAW_URL"
echo "PR URL:    https://github.com/$OWNER/$REPO/pull/$PR_NUMBER"

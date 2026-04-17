#!/usr/bin/env bash
# Upload a demo asset to GitHub user-attachments via the gh-image extension,
# then prepend the embed to the current PR's description — preserving all
# existing content (screenshots, prose, review notes).
#
# Hosts the asset on GitHub's session-gated user-attachments storage. Does NOT
# commit the file to the PR branch. Both the skill's guidance and the user's
# documented preference forbid committing demo assets to git.
#
# Usage:
#   upload-to-pr.sh <file>                  # upload + prepend embed to PR body
#   upload-to-pr.sh <file> --upload-only    # upload + print URL, don't touch PR body
#   upload-to-pr.sh <file> --dry-run        # validate env + PR, don't upload
#   upload-to-pr.sh <file> --replace        # allow prepending even if body already has an asset URL
#
# Idempotency: gh-image mints a new UUID on every upload, so the "URL already
# present" check from older versions of this script doesn't protect against
# accidental re-runs. By default, if the PR body already contains any
# user-attachments URL, this script aborts with instructions. Use --replace to
# override (e.g. if you're intentionally adding a second video).
#
# Prior versions of this script took a [remote-path] second argument to route
# through the Contents API; that path is gone. A positional arg in that slot is
# accepted (for back-compat) but warned and ignored.
#
# Fallbacks if gh-image is unavailable: see SKILL.md "Phase 5 — Delivery". Never
# commit the asset to the PR branch or any shared repo.

set -euo pipefail

# ── arg parsing ──────────────────────────────────────────────────────────
LOCAL=""
MODE="full"        # full | upload-only | dry-run
REPLACE=0          # allow prepending when body already has a user-attachments URL
LEGACY_WARNED=0

_reject_if_mode_set() {
  if [[ "$MODE" != "full" ]]; then
    echo "Error: --upload-only and --dry-run are mutually exclusive." >&2
    exit 2
  fi
}

for arg in "$@"; do
  case "$arg" in
    --upload-only) _reject_if_mode_set; MODE="upload-only" ;;
    --dry-run)     _reject_if_mode_set; MODE="dry-run" ;;
    --replace)     REPLACE=1 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "Unknown flag: $arg" >&2
      exit 2
      ;;
    *)
      if [[ -z "$LOCAL" ]]; then
        LOCAL="$arg"
      elif [[ "$LEGACY_WARNED" -eq 0 ]]; then
        echo "Warning: positional 'remote-path' argument is no longer used (gh-image manages URLs). Ignoring." >&2
        LEGACY_WARNED=1
      fi
      ;;
  esac
done

if [[ -z "$LOCAL" ]]; then
  echo "Usage: upload-to-pr.sh <file> [--upload-only|--dry-run]" >&2
  exit 2
fi

if [[ ! -f "$LOCAL" ]]; then
  echo "File not found: $LOCAL" >&2
  exit 1
fi

# ── pre-flight ───────────────────────────────────────────────────────────
command -v gh >/dev/null 2>&1 || { echo "gh CLI not installed. Run scripts/ensure-webreel.sh." >&2; exit 1; }

if ! gh extension list 2>/dev/null | grep -q "gh image"; then
  echo "gh-image extension not installed. Run scripts/ensure-webreel.sh." >&2
  exit 1
fi

# Verify session token (gh image uses browser cookies, not a PAT).
if ! gh image check-token >/dev/null 2>&1; then
  echo "gh-image session token missing/expired." >&2
  echo "Run: gh image extract-token" >&2
  exit 1
fi

# Resolve PR + repo metadata (fails if no PR open on current branch).
PR_NUMBER=$(gh pr view --json number -q .number 2>/dev/null) || {
  echo "No PR open on the current branch. Push a branch and open a PR first." >&2
  exit 1
}
OWNER=$(gh repo view --json owner -q .owner.login)
REPO=$(gh repo view --json name -q .name)

echo "Target: PR #${PR_NUMBER} on ${OWNER}/${REPO}"
echo "File:   ${LOCAL}"
echo "Mode:   ${MODE}"

# Pre-upload body check: gh-image mints a new UUID per upload, so we can't
# idempotent-check by URL after the fact. Before doing anything expensive,
# check whether the body already has ANY user-attachments URL and bail with
# instructions if so. Runs for both full and dry-run (dry-run is a "would
# this succeed?" check, and must detect the same footgun).
# Skipped for --upload-only (never touches the body).
if [[ "$MODE" != "upload-only" ]]; then
  EXISTING_BODY=$(gh pr view "$PR_NUMBER" --json body -q .body)
  if [[ "$REPLACE" -eq 0 ]] && grep -qE 'user-attachments/assets/' <<< "$EXISTING_BODY"; then
    echo "" >&2
    echo "PR body already contains a user-attachments URL." >&2
    echo "gh-image produces a new UUID per upload, so re-running would leave a duplicate in the body." >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  1. Remove the old URL from the PR body manually, then re-run." >&2
    echo "  2. Re-run with --upload-only to get a fresh URL and embed it yourself." >&2
    echo "  3. Re-run with --replace to prepend anyway (original stays in place; you'll have two URLs)." >&2
    exit 1
  fi
fi

if [[ "$MODE" == "dry-run" ]]; then
  echo "  (dry-run: env OK, PR resolved. Re-run without --dry-run to upload.)"
  exit 0
fi

# ── upload via gh-image ─────────────────────────────────────────────────
echo "Uploading via gh image…"
OUTPUT=$(gh image --repo "${OWNER}/${REPO}" "$LOCAL" 2>&1) || {
  echo "gh image failed:" >&2
  echo "$OUTPUT" >&2
  exit 1
}

# gh image prints a markdown embed like: ![name.mp4](https://github.com/user-attachments/assets/<uuid>)
URL=$(echo "$OUTPUT" | grep -oE 'https://github\.com/user-attachments/assets/[a-f0-9-]+' | head -1)
if [[ -z "$URL" ]]; then
  echo "Failed to parse URL from gh image output:" >&2
  echo "$OUTPUT" >&2
  exit 1
fi

echo "  ✓ uploaded: $URL"

if [[ "$MODE" == "upload-only" ]]; then
  echo ""
  echo "Embed URL: $URL"
  echo "(PR body not modified — use upload-to-pr.sh without --upload-only to prepend automatically.)"
  exit 0
fi

# ── build the embed snippet ──────────────────────────────────────────────
# GitHub auto-renders bare user-attachments URLs as <video> players for MP4 /
# WebM. For images, we need explicit markdown image syntax.
EXT="${LOCAL##*.}"
# tr for lowercase — ${EXT,,} is bash 4+, macOS ships bash 3.2
EXT_LOWER=$(printf '%s' "$EXT" | tr '[:upper:]' '[:lower:]')
case "$EXT_LOWER" in
  mp4|webm|mov) EMBED="$URL" ;;                  # bare URL → auto-video-player
  gif|png|jpg|jpeg) EMBED="![demo]($URL)" ;;     # image markdown
  *) EMBED="[Demo]($URL)" ;;                      # link for unknown types
esac

# ── PR body edit ──────────────────────────────────────────────────────────
# EXISTING_BODY was fetched earlier (before upload) for the --replace pre-check.
# The URL-collision check below is belt-and-suspenders: the pre-check already
# guaranteed no conflicting user-attachments URL exists, unless --replace was
# passed, in which case we still want to avoid literal URL duplicates.
if grep -qF "$URL" <<< "$EXISTING_BODY"; then
  echo "  ⚠ embed URL already present in PR body; skipping body edit"
else
  BODY_FILE=$(mktemp)
  trap 'rm -f "$BODY_FILE"' EXIT
  printf '%s\n\n%s\n' "$EMBED" "$EXISTING_BODY" > "$BODY_FILE"
  gh pr edit "$PR_NUMBER" --body-file "$BODY_FILE"
  echo "  ✓ PR #${PR_NUMBER} body updated (embed prepended, existing content preserved)"
fi

echo ""
echo "Embed URL: $URL"
echo "PR URL:    https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}"

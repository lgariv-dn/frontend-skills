#!/usr/bin/env bash
# Verify the webreel CLI, companion Claude skill, gh CLI, and the gh-image
# extension are all available. webreel + its skill are installed if missing.
# gh CLI missing -> prompt and exit (must be installed by the user).
# gh-image extension missing -> auto-install (no prompt).

set -euo pipefail

WEBREEL_SKILL_DIR="$HOME/.claude/skills/webreel"
WEBREEL_SKILL_FILES=(SKILL.md examples.md steps-reference.md)
WEBREEL_SKILL_RAW_BASE="https://raw.githubusercontent.com/lgariv-dn/webreel/feat/autozoom/skills/webreel"
GH_IMAGE_EXT="drogers0/gh-image"

# ── 1. CLI ─────────────────────────────────────────────────────────────────
cli_source=""
cli_version=""
if command -v webreel >/dev/null 2>&1; then
  cli_source="global"
  cli_version="$(webreel --version 2>/dev/null || echo unknown)"
elif npx --no-install webreel --version >/dev/null 2>&1; then
  cli_source="project-local"
  cli_version="$(npx --no-install webreel --version 2>/dev/null || echo unknown)"
fi

if [[ -z "$cli_source" ]]; then
  echo "webreel CLI not found on PATH or in the local node_modules."
  printf "Install globally via 'npm install -g @lgariv/webreel'? [y/N] "
  read -r reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    npm install -g @lgariv/webreel
    cli_version="$(webreel --version 2>/dev/null || echo installed)"
    cli_source="global"
  else
    echo "Aborted. Install manually or add '@lgariv/webreel' to the project devDependencies."
    exit 1
  fi
fi
echo "webreel CLI: $cli_version ($cli_source)"

# ── 2. Companion skill ─────────────────────────────────────────────────────
skill_missing=()
for f in "${WEBREEL_SKILL_FILES[@]}"; do
  [[ -f "$WEBREEL_SKILL_DIR/$f" ]] || skill_missing+=("$f")
done

if [[ ${#skill_missing[@]} -eq 0 ]]; then
  echo "webreel companion skill: installed at $WEBREEL_SKILL_DIR"
else
  echo "webreel companion skill: missing ${#skill_missing[@]}/${#WEBREEL_SKILL_FILES[@]} file(s) at $WEBREEL_SKILL_DIR"
  printf "Fetch the skill from lgariv-dn/webreel on GitHub? [y/N] "
  read -r reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    mkdir -p "$WEBREEL_SKILL_DIR"
    fetch_errors=0
    for f in "${WEBREEL_SKILL_FILES[@]}"; do
      if ! curl -fsSL "$WEBREEL_SKILL_RAW_BASE/$f" -o "$WEBREEL_SKILL_DIR/$f"; then
        echo "  ✗ failed to fetch $f"
        fetch_errors=$((fetch_errors + 1))
      else
        echo "  ✓ $f"
      fi
    done
    if [[ $fetch_errors -gt 0 ]]; then
      echo "One or more files failed to download. Check your network and retry."
      exit 1
    fi
    echo "webreel companion skill: installed to $WEBREEL_SKILL_DIR"
  else
    echo "Skipped. Install manually:"
    echo "  mkdir -p $WEBREEL_SKILL_DIR"
    for f in "${WEBREEL_SKILL_FILES[@]}"; do
      echo "  curl -fsSL $WEBREEL_SKILL_RAW_BASE/$f -o $WEBREEL_SKILL_DIR/$f"
    done
    exit 1
  fi
fi

# ── 3. Cached runtime deps (auto-downloaded by webreel on first run) ────────
chrome_dir="$HOME/.webreel/bin/chrome"
if [[ -d "$chrome_dir" ]]; then
  echo "webreel chrome: cached at $chrome_dir"
else
  echo "webreel chrome: will auto-download on first 'webreel record'"
fi

ffmpeg_dir="$HOME/.webreel/bin/ffmpeg"
if [[ -d "$ffmpeg_dir" ]]; then
  echo "webreel ffmpeg: cached at $ffmpeg_dir"
else
  echo "webreel ffmpeg: will auto-download on first 'webreel record'"
fi

# ── 4. GitHub CLI (required for PR metadata + gh-image upload) ─────────────
if ! command -v gh >/dev/null 2>&1; then
  cat <<'EOF' >&2

✗ GitHub CLI (gh) is not installed.

The pr-demo-recorder skill relies on `gh` for:
  - reading PR / branch / repo metadata
  - uploading demo videos to GitHub user-attachments (via the gh-image extension)

Install it first, then re-run this check:

  macOS:   brew install gh
  Linux:   see https://github.com/cli/cli/blob/trunk/docs/install_linux.md
  Windows: winget install --id GitHub.cli

After install, authenticate with:  gh auth login

Aborting.
EOF
  exit 1
fi
gh_version="$(gh --version 2>/dev/null | head -n1 || echo unknown)"
echo "gh CLI: $gh_version"

# Require an authenticated gh so downstream PR operations don't surprise-fail.
if ! gh auth status >/dev/null 2>&1; then
  echo "✗ gh is installed but not authenticated. Run: gh auth login" >&2
  exit 1
fi

# ── 5. gh-image extension (for programmatic user-attachments upload) ───────
if gh extension list 2>/dev/null | awk '{print $3}' | grep -qx "$GH_IMAGE_EXT"; then
  echo "gh-image extension: installed ($GH_IMAGE_EXT)"
else
  echo "gh-image extension: not installed — installing $GH_IMAGE_EXT..."
  if gh extension install "$GH_IMAGE_EXT" >/dev/null 2>&1; then
    echo "  ✓ installed"
  else
    echo "  ✗ install failed. Try manually: gh extension install $GH_IMAGE_EXT" >&2
    exit 1
  fi
fi

exit 0

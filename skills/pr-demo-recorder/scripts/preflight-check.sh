#!/usr/bin/env bash
# preflight-check.sh — validate the environment before recording a webreel demo.
#
# Complements (does not replace) ensure-webreel.sh:
#   - ensure-webreel.sh  → verifies the TOOLS are installed (CLI, skill, gh, extension)
#   - preflight-check.sh → verifies the TARGET ENVIRONMENT is healthy for recording
#
# Checks (in order; each check prints PASS/FAIL/SKIP and the reason):
#   1. URL hard-navigates (returns HTML, not a bare "Not Found" text response)
#   2. URL renders expected content text (verifies waitFor candidate before recording)
#   3. Dev server root responds 200
#   4. gh-image session token is valid
#   5. Chromium / ffmpeg / node present (webreel needs these)
#   6. Sufficient disk space for raw frames (~200 MB per minute of recording)
#   7. No other webreel process currently recording in this directory
#
# Usage:
#   preflight-check.sh <url> [--expect "<text>"]
#   preflight-check.sh http://localhost:4200/ --expect "Welcome back"
#
# Exits 0 if all PASS, 1 if any FAIL (SKIP doesn't fail).

set -uo pipefail

URL=""
EXPECT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect) EXPECT="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) URL="$1"; shift ;;
  esac
done

if [[ -z "$URL" ]]; then
  echo "Usage: preflight-check.sh <url> [--expect \"<text>\"]" >&2
  exit 1
fi

PASS="\033[32m✓ PASS\033[0m"
FAIL="\033[31m✗ FAIL\033[0m"
SKIP="\033[33m- SKIP\033[0m"
failures=0

pass() { printf "  %b %s\n" "$PASS" "$*"; }
fail() { printf "  %b %s\n" "$FAIL" "$*"; failures=$((failures + 1)); }
skip() { printf "  %b %s\n" "$SKIP" "$*"; }

echo "Pre-flight check: $URL"
echo

# ── 1. URL returns HTML (not SPA 404 "Not Found") ──
echo "[1/7] URL hard-navigation returns HTML"
body=$(curl -sS --max-time 10 "$URL" 2>/dev/null || echo "")
if [[ -z "$body" ]]; then
  fail "no response from $URL (is the dev server up?)"
elif [[ "$body" == "Not Found" ]] || { [[ "$body" != *"<html"* ]] && [[ "$body" != *"<!DOCTYPE"* ]]; }; then
  fail "response is not HTML (likely SPA 404). Run scripts/list-routes.py to find the right URL."
  fail "  sample: $(echo "$body" | head -c 200)"
else
  pass "HTML returned"
fi

# ── 2. Expected content text present (if --expect was given) ──
echo "[2/7] Expected content text present"
if [[ -z "$EXPECT" ]]; then
  skip "no --expect provided (pass --expect \"<text>\" to verify waitFor candidates)"
elif [[ -z "${body:-}" ]]; then
  skip "skipped (URL didn't return a body)"
elif [[ "$body" == *"$EXPECT"* ]]; then
  pass "found \"$EXPECT\" in response body (server-rendered or static)"
else
  # SPAs render content via JS — the initial HTML is usually just a shell with a
  # root <div> and bootstrap <script> tags. A missing --expect string in that
  # case is expected, not a failure.
  if [[ "$body" == *'id="root"'* ]] || [[ "$body" == *'id="app"'* ]] || [[ "$body" == *"<script"* ]]; then
    skip "SPA shell detected — \"$EXPECT\" isn't in initial HTML (that's fine; webreel will still wait for it at runtime)"
  else
    fail "\"$EXPECT\" NOT in response body, and response doesn't look like an SPA shell"
  fi
fi

# ── 3. Dev server root responds ──
echo "[3/7] Dev server root responds"
root_code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 "$(echo "$URL" | awk -F/ '{print $1 "//" $3}')/" 2>/dev/null || echo "000")
if [[ "$root_code" == "200" ]]; then
  pass "root returns 200"
else
  fail "root returned HTTP $root_code"
fi

# ── 4. gh-image token ──
echo "[4/7] gh-image session token valid"
if ! command -v gh >/dev/null 2>&1; then
  skip "gh CLI not installed (install via ensure-webreel.sh)"
elif ! gh extension list 2>/dev/null | grep -q "gh image"; then
  skip "gh-image extension not installed (install via ensure-webreel.sh)"
else
  if gh image check-token >/dev/null 2>&1; then
    pass "token valid"
  else
    fail "token missing or expired (run: gh image extract-token)"
  fi
fi

# ── 5. Binaries (chromium, ffmpeg, node) ──
echo "[5/7] Required binaries present"
for bin in node npx; do
  if command -v "$bin" >/dev/null 2>&1; then
    pass "$bin found ($($bin --version 2>/dev/null | head -1))"
  else
    fail "$bin missing"
  fi
done
# Chromium + ffmpeg are webreel-managed. Just verify the install dir exists.
if [[ -d "$HOME/.webreel" ]] || command -v ffmpeg >/dev/null 2>&1; then
  pass "webreel/ffmpeg binaries appear available"
else
  skip "no ~/.webreel yet — first `npx webreel record` will download them"
fi

# ── 6. Disk space ──
# Use `df -k` (POSIX kilobytes) for portability — works on both macOS and Linux.
# Convert to GB by dividing by 1024*1024. macOS `df -g` would also work but is
# not available on all Linux distros.
echo "[6/7] Disk space for raw frames"
available_kb=$(df -k . 2>/dev/null | awk 'NR==2 {print $4}')
if [[ -z "$available_kb" ]] || ! [[ "$available_kb" =~ ^[0-9]+$ ]]; then
  skip "could not read disk space (df exit unexpected)"
else
  available_gb=$((available_kb / 1024 / 1024))
  if [[ "$available_gb" -ge 2 ]]; then
    pass "${available_gb}G free"
  elif [[ "$available_gb" -ge 1 ]]; then
    skip "${available_gb}G free (tight — fine for short demos, may run out for >2 min recordings)"
  else
    fail "less than 1G free — free up disk before recording"
  fi
fi

# ── 7. No other webreel process recording here ──
echo "[7/7] No other webreel process in this directory"
cwd_basename=$(basename "$(pwd)")
other_pid=$(pgrep -f "webreel.*record" 2>/dev/null | head -1 || true)
if [[ -z "$other_pid" ]]; then
  pass "no webreel record process running"
else
  # Only fail if the other process is in this directory
  other_cwd=$(lsof -p "$other_pid" -d cwd 2>/dev/null | awk 'NR==2 {print $NF}')
  if [[ "$other_cwd" == "$(pwd)" ]]; then
    fail "another webreel record process (pid $other_pid) is active in this directory"
  else
    skip "another webreel process exists (pid $other_pid) but not in this directory"
  fi
fi

echo
if [[ "$failures" -eq 0 ]]; then
  echo "Pre-flight passed. Safe to record."
  exit 0
else
  echo "Pre-flight FAILED ($failures issue(s)). Fix before recording." >&2
  exit 1
fi

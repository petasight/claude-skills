#!/usr/bin/env bash
# edit-refactor-nudge.sh — PostToolUse(Edit|Write|MultiEdit) hook
#
# Fires after every code edit. Uses a per-session counter to nudge at most
# once every 10 edits, so the context window does not get spammed.
#
# Fixes applied from review_and_usage.pdf:
#   3. flock for atomic counter increment (race condition fix)
#   4. jq dependency check with graceful fallback
#   5. Configurable paths via env vars
#
# Always exits 0 (non-blocking).

set -euo pipefail

# --- Config (override via env vars) ---
NUDGE_INTERVAL="${NUDGE_INTERVAL:-10}"

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo "{}"
  exit 0
fi

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"')"
counter_file="/tmp/claude-refactor-nudge-${session_id}.count"

# --- Atomic counter increment with flock (PDF fix #3) ---
count=0
(
  flock -x 200
  [[ -f "$counter_file" ]] && count="$(cat "$counter_file" 2>/dev/null || echo 0)"
  count=$((count + 1))
  echo "$count" > "$counter_file"
  echo "$count"
) 200>"${counter_file}.lock"

# Re-read after lock release
count="$(cat "$counter_file" 2>/dev/null || echo 1)"

if (( count % NUDGE_INTERVAL == 1 )); then
  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Refactor checkpoint: several edits made this session. Quick self-check — duplication, dead branches, premature abstraction, over-long functions, leaked secrets? If any apply, invoke the refactoring-specialist agent now. The merge-to-dev/main gate will catch it later, but fixing in flight is cheaper."
  }
}
JSON
else
  echo "{}"
fi

exit 0

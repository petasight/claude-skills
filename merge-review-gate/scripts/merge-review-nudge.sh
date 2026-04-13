#!/usr/bin/env bash
# merge-review-nudge.sh — PreToolUse(Bash) hook
#
# Fires when Claude is about to run `git merge` or `git push`. If the target
# branch is dev/main/master, injects an additionalContext reminder telling
# Claude to invoke the merge-review-gate skill (three-role parallel review).
#
# Fixes applied from review_and_usage.pdf:
#   1. Simplified branch matching (no fragile regex)
#   2. jq dependency check with graceful fallback
#   3. Configurable paths via env vars
#
# Always exits 0 (non-blocking).

set -euo pipefail

# --- Config (override via env vars) ---
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
# Protected branches — space-separated. Override to match your workflow.
PROTECTED_BRANCHES="${PROTECTED_BRANCHES:-dev main master}"

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"WARNING: jq not installed — merge-review-nudge hook cannot parse input. Install with: brew install jq"}}'
  exit 0
fi

input="$(cat)"
command="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"

# --- Simplified branch detection (PDF fix #1) ---
# Instead of fragile regex parsing of git push args, check if any protected
# branch name appears as a token in the command. Less precise but far more
# robust against flag ordering, refspecs, and remote name variations.
should_trigger=false

if [[ "$command" == *"git merge"* ]] || [[ "$command" == *"git push"* ]]; then
  for base in $PROTECTED_BRANCHES; do
    for branch in "$base" "origin/${base}"; do
    if [[ "$command" == *" ${branch}"* ]] || [[ "$command" == *" ${branch} "* ]] || [[ "$command" == *":${branch}"* ]]; then
      should_trigger=true
      break 2
    fi
    done
  done
fi

if [[ "$should_trigger" == "true" ]]; then
  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "MERGE GATE (dev/main): before this merge/push completes, invoke the merge-review-gate skill to run a full three-role review in parallel. (1) refactoring-specialist agent — dead code, smells, dedup, premature abstraction. (2) architect-reviewer agent — module boundaries, layering, coupling, scalability. (3) Trail of Bits security skills — differential-review, sharp-edges, insecure-defaults, supply-chain-risk-auditor. Apply non-trivial fixes BEFORE completing the merge. This is the only gate — do not skip."
  }
}
JSON
else
  echo "{}"
fi

exit 0

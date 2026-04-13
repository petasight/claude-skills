#!/usr/bin/env bash
# setup.sh — Fully automated setup for the merge-review-gate skill
#
# Installs:
#   - VoltAgent refactoring-specialist + architect-reviewer agents
#   - Trail of Bits security skills (4 skills, flat install)
#   - Hook scripts (merge-review-nudge.sh, edit-refactor-nudge.sh)
#   - Patches settings.json automatically (no manual editing)
#
# Addresses all 6 flaws from review_and_usage.pdf:
#   1. Simplified branch matching in hook scripts
#   2. Fully automated Trail of Bits install (no manual intervention)
#   3. Atomic counter with flock in edit-refactor-nudge
#   4. jq dependency check in both hooks
#   5. Configurable base paths
#   6. Automated settings.json patching via jq
#
# Usage: ./setup.sh [--claude-dir DIR]
#
# Idempotent — safe to run multiple times.

set -euo pipefail

# --- Configurable paths ---
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
ARCHIVE_DATE="$(date +%Y-%m-%d)"
ARCHIVE_DIR="${CLAUDE_DIR}/_archive/${ARCHIVE_DATE}-prereplace"

# Parse CLI args
while [[ $# -gt 0 ]]; do
  case $1 in
    --claude-dir) CLAUDE_DIR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
AGENTS_DIR="${CLAUDE_DIR}/agents"
SKILLS_DIR="${CLAUDE_DIR}/skills"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Preflight checks ---
echo "=== Merge Review Gate — Setup ==="
echo "Claude dir:  ${CLAUDE_DIR}"
echo ""

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required. Install with: brew install jq (macOS) or apt install -y jq (Linux)"
  exit 1
fi

if ! command -v git &>/dev/null; then
  echo "ERROR: git is required."
  exit 1
fi

# --- Step 1: Archive existing tools ---
echo "[1/6] Archiving replaced agents/skills..."
mkdir -p "$ARCHIVE_DIR"
for f in "${AGENTS_DIR}/architect.md" \
         "${AGENTS_DIR}/security-expert.md"; do
  [[ -f "$f" ]] && mv "$f" "$ARCHIVE_DIR/" && echo "  Archived: $(basename "$f")"
done
[[ -d "${SKILLS_DIR}/security-review" ]] && \
  mv "${SKILLS_DIR}/security-review" "$ARCHIVE_DIR/" && \
  echo "  Archived: security-review/"
echo ""

# --- Step 2: Install VoltAgent agents ---
echo "[2/6] Installing VoltAgent subagents..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git clone --depth 1 --quiet https://github.com/VoltAgent/awesome-claude-code-subagents.git "$TMP/voltagent"
mkdir -p "${AGENTS_DIR}"
cp "$TMP/voltagent/categories/06-developer-experience/refactoring-specialist.md" \
   "${AGENTS_DIR}/refactoring-specialist.md"
cp "$TMP/voltagent/categories/04-quality-security/architect-reviewer.md" \
   "${AGENTS_DIR}/architect-reviewer.md"
echo "  Installed: refactoring-specialist.md, architect-reviewer.md"
echo ""

# --- Step 3: Install Trail of Bits security skills (PDF fix #2 — fully automated) ---
echo "[3/6] Installing Trail of Bits security skills..."
git clone --depth 1 --quiet https://github.com/trailofbits/skills.git "$TMP/tob"
mkdir -p "${SKILLS_DIR}"

# Explicit copies — no manual inspection required
for skill in differential-review sharp-edges insecure-defaults supply-chain-risk-auditor; do
  src="$TMP/tob/plugins/${skill}/skills/${skill}"
  if [[ -d "$src" ]]; then
    cp -r "$src" "${SKILLS_DIR}/"
    echo "  Installed: ${skill}/"
  else
    echo "  WARNING: ${skill} not found at expected path, skipping"
  fi
done
echo ""

# --- Step 4: Install hook scripts ---
echo "[4/6] Installing hook scripts..."
mkdir -p "$HOOKS_DIR"
cp "${SCRIPT_DIR}/merge-review-nudge.sh" "${HOOKS_DIR}/"
cp "${SCRIPT_DIR}/edit-refactor-nudge.sh" "${HOOKS_DIR}/"
chmod +x "${HOOKS_DIR}/merge-review-nudge.sh" "${HOOKS_DIR}/edit-refactor-nudge.sh"
echo "  Installed: merge-review-nudge.sh, edit-refactor-nudge.sh"
echo ""

# --- Step 5: Patch settings.json (PDF fix #6 — automated via jq) ---
echo "[5/6] Patching settings.json..."
if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo '{}' > "$SETTINGS_FILE"
fi

# Backup
cp "$SETTINGS_FILE" "${SETTINGS_FILE}.bak.${ARCHIVE_DATE}"

# Build the new hook entries
MERGE_HOOK_ENTRY='{"matcher":"Bash","hooks":[{"type":"command","command":"~/.claude/hooks/merge-review-nudge.sh"}]}'
PUSH_HOOK_ENTRY='{"matcher":"Bash","hooks":[{"type":"command","command":"~/.claude/hooks/merge-review-nudge.sh"}]}'
EDIT_HOOK_ENTRY='{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"~/.claude/hooks/edit-refactor-nudge.sh"}]}'

# Ensure hooks arrays exist, then append only if not already present
PATCHED=$(jq \
  --argjson merge "$MERGE_HOOK_ENTRY" \
  --argjson push "$PUSH_HOOK_ENTRY" \
  --argjson edit "$EDIT_HOOK_ENTRY" \
  '
  .hooks //= {} |
  .hooks.PreToolUse //= [] |
  .hooks.PostToolUse //= [] |
  # Add merge hook if not already present
  (if (.hooks.PreToolUse | map(select(.hooks[]?.command == "~/.claude/hooks/merge-review-nudge.sh")) | length) == 0
   then .hooks.PreToolUse += [$merge, $push]
   else . end) |
  # Add edit hook if not already present
  (if (.hooks.PostToolUse | map(select(.hooks[]?.command == "~/.claude/hooks/edit-refactor-nudge.sh")) | length) == 0
   then .hooks.PostToolUse += [$edit]
   else . end)
  ' "$SETTINGS_FILE")

echo "$PATCHED" > "$SETTINGS_FILE"
echo "  Patched: ${SETTINGS_FILE}"
echo "  Backup:  ${SETTINGS_FILE}.bak.${ARCHIVE_DATE}"
echo ""

# --- Step 6: Verify ---
echo "[6/6] Verifying..."
ERRORS=0

for agent in refactoring-specialist architect-reviewer; do
  if [[ -f "${AGENTS_DIR}/${agent}.md" ]]; then
    echo "  OK: ${agent} agent"
  else
    echo "  FAIL: ${agent} agent not found"; ERRORS=$((ERRORS + 1))
  fi
done

for skill in differential-review sharp-edges insecure-defaults supply-chain-risk-auditor; do
  if [[ -d "${SKILLS_DIR}/${skill}" ]]; then
    echo "  OK: ${skill} skill"
  else
    echo "  FAIL: ${skill} skill not found"; ERRORS=$((ERRORS + 1))
  fi
done

for hook in merge-review-nudge.sh edit-refactor-nudge.sh; do
  if [[ -x "${HOOKS_DIR}/${hook}" ]]; then
    echo "  OK: ${hook}"
  else
    echo "  FAIL: ${hook} not found or not executable"; ERRORS=$((ERRORS + 1))
  fi
done

if jq . "$SETTINGS_FILE" >/dev/null 2>&1; then
  echo "  OK: settings.json is valid JSON"
else
  echo "  FAIL: settings.json is invalid JSON"; ERRORS=$((ERRORS + 1))
fi

echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "=== Setup complete. Restart Claude Code for hooks to take effect. ==="
else
  echo "=== Setup finished with ${ERRORS} error(s). Check output above. ==="
  exit 1
fi

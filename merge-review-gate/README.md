# merge-review-gate

Three-persona automated review gate for Claude Code. Runs refactoring, architecture, and security reviews in parallel before any merge to `dev`/`main` completes.

## What it does

Every merge to a protected branch triggers three reviewers simultaneously:

| Role | Source | Focus |
|------|--------|-------|
| **Refactoring Engineer** | [VoltAgent](https://github.com/VoltAgent/awesome-claude-code-subagents) `refactoring-specialist` | Dead code, duplication, smells, over-abstraction |
| **Software Architect** | [VoltAgent](https://github.com/VoltAgent/awesome-claude-code-subagents) `architect-reviewer` | Module boundaries, coupling, patterns, scalability |
| **Security Engineer** | [Trail of Bits](https://github.com/trailofbits/skills) (4 skills) | Diff review, footgun APIs, secrets/weak auth, dependency CVEs |

Plus a lightweight refactor checkpoint that nudges every 10 edits during a session.

## Install

```bash
git clone https://github.com/petasight/claude-skills.git
cd claude-skills/merge-review-gate
chmod +x scripts/*.sh
./scripts/setup.sh
```

Setup is fully automated — no manual file editing. Idempotent (safe to re-run).

### Custom paths and branches

```bash
CLAUDE_DIR=~/my-claude ./scripts/setup.sh
# or
./scripts/setup.sh --claude-dir ~/my-claude
```

Protected branches default to `dev main master`. Override via env var:

```bash
export PROTECTED_BRANCHES="dev main staging"
```

### Prerequisites

- Claude Code v2.1.85+
- `jq` (`brew install jq` / `apt install -y jq`)
- `git`

## How it works

### Hook 1: Merge gate (PreToolUse)

When Claude is about to run `git merge` or `git push`, `merge-review-nudge.sh` checks if the target is a protected branch (configurable via `PROTECTED_BRANCHES`, defaults to `dev main master`). If yes, it injects an `additionalContext` reminder telling Claude to spawn all three reviewers in parallel before completing the merge.

Non-blocking by design. Claude is strongly nudged but not forced — this avoids friction from false positives. To switch to blocking mode, change `permissionDecision` from `"allow"` to `"deny"` in the script.

### Hook 2: Edit checkpoint (PostToolUse)

After every code edit, `edit-refactor-nudge.sh` increments a per-session counter. On the 1st, 11th, 21st... edit, it reminds Claude to self-check for common smells and invoke the refactoring agent if needed.

Uses `flock` for atomic counter updates. Counter resets per session.

## Manual invocation

Even without hooks, you can trigger the review by telling Claude:

> "run the merge review gate on my changes"

or by invoking the skill directly.

## Cost / latency

- **Hooks**: ~5ms per fire (bash + jq), zero token cost
- **Reviewers**: 3 parallel agents on merge — ~30-90s, ~$0.10-$0.40 per merge depending on diff size and model
- **Edit nudge**: text-only reminder, negligible cost

## Uninstall

```bash
# Remove agents
rm ~/.claude/agents/refactoring-specialist.md
rm ~/.claude/agents/architect-reviewer.md

# Remove skills
rm -rf ~/.claude/skills/{differential-review,sharp-edges,insecure-defaults,supply-chain-risk-auditor}

# Remove hooks
rm ~/.claude/hooks/merge-review-nudge.sh ~/.claude/hooks/edit-refactor-nudge.sh

# Manually remove the hook entries from ~/.claude/settings.json
```

Archived originals are in `~/.claude/_archive/<date>-prereplace/`.

## License

CC-BY-SA-4.0 — see [LICENSE](./LICENSE).

Incorporates components from [VoltAgent](https://github.com/VoltAgent/awesome-claude-code-subagents) (MIT) and [Trail of Bits](https://github.com/trailofbits/skills) (CC-BY-SA-4.0).

---
name: merge-review-gate
version: 2.0.0
description: |
  Three-role automated review gate for merges to dev/main. Spawns refactoring
  engineer, software architect, and security engineer reviewers in parallel
  before any merge completes. Use as a pre-merge quality gate or on-demand.
  Activates on: "review before merge", "merge gate", "run reviewers",
  "three-role review", "pre-merge review", "merge review gate".
allowed-tools:
  - Read
  - Bash
  - Glob
  - Grep
  - Agent
  - Edit
  - Write
---

# Merge Review Gate

Three-persona review that runs automatically on merges to `dev`/`main` (via hooks) or on-demand when this skill is invoked.

## Reviewers

| # | Role | Agent | Model | Focus |
|---|------|-------|-------|-------|
| 1 | Refactoring Engineer | `refactoring-specialist` | Sonnet | Dead code, smells, dedup, premature abstraction, simplification |
| 2 | Software Architect | `architect-reviewer` | Opus | Module boundaries, layering, coupling, design patterns, scalability |
| 3 | Security Engineer | Trail of Bits skills | Sonnet | PR diff scan, footgun APIs, secrets/weak auth, dependency CVEs |

## Step 1: Identify Changes

```bash
# If merging a branch
git diff --name-only HEAD...$(git branch --show-current) 2>/dev/null || git diff --name-only HEAD~5..HEAD
```

If invoked manually (not from a hook), determine the diff scope from context — branch diff, staged changes, or last N commits.

## Step 2: Spawn All Three Reviewers in Parallel

Launch these three agents simultaneously via the Agent tool. Do NOT run them sequentially.

### Agent 1: Refactoring Specialist

```
Analyze the following diff for refactoring opportunities. Focus on:
- Dead code and unused imports
- Code duplication (DRY violations)
- Premature or unnecessary abstractions
- Functions exceeding 50 lines
- Deep nesting (>4 levels)
- Leaked secrets or debug statements
Report each finding as: [SEVERITY] file:line — description → fix
```

### Agent 2: Architect Reviewer

```
Review the following diff for architectural quality. Focus on:
- Module boundary violations (cross-layer imports, circular deps)
- Coupling between unrelated domains
- Missing or misplaced abstractions
- Scalability concerns (N+1 queries, unbounded loops, missing pagination)
- Consistency with existing patterns in the codebase
Report each finding as: [SEVERITY] file:line — description → fix
```

### Agent 3: Security Engineer (Trail of Bits skills)

```
Run a security audit on the following diff. Check:
- differential-review: scan the PR diff for introduced vulnerabilities
- sharp-edges: flag use of dangerous/footgun APIs (eval, innerHTML, raw SQL, subprocess with shell=True)
- insecure-defaults: secrets in code, weak auth config, permissive CORS, missing rate limits
- supply-chain-risk-auditor: new dependencies with known CVEs or low trust scores
Report each finding as: [SEVERITY] file:line — description → fix
```

## Step 3: Consolidate and Act

After all three agents complete:

1. **Merge findings** into a single report, deduplicated, sorted by severity (CRITICAL > HIGH > MEDIUM > LOW)
2. **Auto-fix** non-trivial issues (CRITICAL and HIGH) before the merge proceeds
3. **Report** remaining findings to the user with a verdict:
   - **BLOCK** — critical issues remain after auto-fix
   - **WARN** — medium issues noted, merge allowed
   - **PASS** — clean

## Step 4: Verdict

```
## Merge Review Gate — Results

**Verdict: [PASS|WARN|BLOCK]**

| Severity | Count | Auto-fixed |
|----------|-------|------------|
| CRITICAL | X     | Y          |
| HIGH     | X     | Y          |
| MEDIUM   | X     | —          |
| LOW      | X     | —          |

### Findings
[list findings here]

### Applied Fixes
[list auto-fixes here]
```

If BLOCK: do not proceed with merge. Fix remaining criticals first.

---

## Setup (Automated Hooks)

To make this gate fire automatically on every merge to dev/main, run the setup script:

```bash
./scripts/setup.sh
```

This installs:
- `merge-review-nudge.sh` — PreToolUse hook that triggers this gate on `git merge`/`git push` to dev/main
- `edit-refactor-nudge.sh` — PostToolUse hook that nudges refactoring every 10 edits
- Patches `settings.json` automatically (no manual editing)

See `scripts/README.md` for details.

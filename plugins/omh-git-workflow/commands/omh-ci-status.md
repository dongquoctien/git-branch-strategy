# CI Status Check (OMH Git Strategy §15 CI Enforcement)

**Usage**: `/omh-ci-status [pr-number-or-branch]`

Examples:
- `/omh-ci-status` — check CI for current branch's PR (or current branch's latest push)
- `/omh-ci-status 42` — check a specific PR
- `/omh-ci-status ELS-123-add-oauth` — check a branch that may not have a PR yet

Parse arguments from: $ARGUMENTS
- Optional: PR number or branch name

---

## Rules (from README §15 CI Enforcement Policy)

Required checks before merge to master (all MUST pass per §15):

| Gate | Scope | Failure action |
|---|---|---|
| Build | All PRs to master | Block merge |
| Unit tests (≥70% coverage) | All PRs to master | Block merge |
| Lint / static analysis | All PRs to master | Block merge |
| SonarQube quality gate | All PRs to master | Block merge |
| AI code review | All PRs to master | Non-blocking; High findings must be addressed |
| Integration tests | staging/release deploys | Block QA sign-off |
| Smoke tests | Post-production deploy | Triggers rollback |

Per §15, CI is **non-bypassable** — even hotfixes must pass CI before merge.

**Flaky test policy**: if a test fails unrelated to the PR, document, re-run once, if still fails — fix the test or Tech Lead approves skip with written justification.

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended.

---

## Workflow

### Step 1 — Resolve target

If `$ARGUMENTS` is:
- A number → treat as PR number
- A branch name → use as branch
- Empty → auto-detect from current branch via `git branch --show-current`

Detect platform from `git remote get-url origin` — GitHub vs Bitbucket.

### Step 2 — Fetch PR and check runs

**GitHub**:
```bash
gh pr view <ref> --json number,url,headRefName,baseRefName,headRefOid,statusCheckRollup,mergeStateStatus 2>/dev/null
```

If no PR found but branch exists, fall back to commit-level checks:
```bash
gh run list --branch <branch> --limit 5 --json databaseId,name,status,conclusion,url,event,headSha
```

**Bitbucket**:
```
mcp__bitbucket__getPullRequestStatuses(..., pull_request_id=<N>)
mcp__bitbucket__listPipelineRuns(..., query="target.branch=<branch>", sort="-created_on")
```

### Step 3 — Parse and classify check results

For each check, extract:
- Name (e.g. `build`, `test-unit`, `lint`, `sonar-gate`, `ai-review`)
- Status: `queued` | `in_progress` | `completed`
- Conclusion (if completed): `success` | `failure` | `cancelled` | `skipped` | `timed_out` | `neutral`
- Duration
- Log URL

Map check names to §15 gates:
- `build*` / `compile*` → **Build**
- `test*` / `unit*` / `jest*` / `vitest*` / `pytest*` → **Unit tests**
- `lint*` / `eslint*` / `flake8*` / `clippy*` → **Lint**
- `sonar*` / `sonarqube*` / `sonarcloud*` → **SonarQube**
- `ai*` / `copilot*` / `claude*` (review job) → **AI review**
- `e2e*` / `integration*` / `cypress*` → **Integration tests**
- `smoke*` → **Smoke tests**

Unknown checks → list as "Other" (still reported, just not mapped to a §15 gate).

### Step 4 — Compute coverage if available

For unit test gate, try to extract coverage:
- GitHub: parse artifact `coverage-report` or step output with "Total coverage:"
- Or check for a dedicated `coverage` check if CI reports it separately

Flag if coverage < 70% per §15.

### Step 5 — Render summary

Print structured dashboard:

```
╔══════════════════════════════════════════════════════╗
║  CI Status — PR #42 · INFRA-005-phase-5a-skills     ║
╚══════════════════════════════════════════════════════╝

┌─ Required gates (§15) ─────────────────────────────┐
│ Build          ✅ success     (42s)                │
│ Unit tests     ✅ success     (3m 12s) · 84% cov   │
│ Lint           ❌ failure     (18s)                │
│ SonarQube      ⏳ in_progress (running 2m)          │
│ AI review      ⚠ 2 high-severity findings          │
└────────────────────────────────────────────────────┘

┌─ Other checks ─────────────────────────────────────┐
│ codeql         ✅ success     (1m 24s)             │
│ dependabot     ⏸ skipped                           │
└────────────────────────────────────────────────────┘

Verdict: NOT READY TO MERGE — Lint failed, SonarQube pending

Failed job logs:
  Lint: <url>
```

Icons:
- ✅ success
- ❌ failure
- ⏳ in_progress / queued
- ⚠ warning (AI review with findings, low coverage, flaky)
- ⏸ cancelled / skipped
- 🔴 timed_out

### Step 6 — Offer next actions

Based on result, prompt via `AskUserQuestion`:

**If any required gate failed**:
```
question: "Gates failed: <names>. What next?"
header:   "Action"
multiSelect: false
options:
  - "Open failed job log(s)" (Recommended) — description: "Print URLs; user opens in browser"
  - "Re-run failed checks" — description: "gh run rerun --failed (same commit)"
  - "Fix locally then push" — description: "Close skill; after push, re-run /omh-ci-status"
  - "Flaky test — request skip" — description: "Per §15 flaky policy: document in PR + TL approval"
```

**If all required green**:
```
question: "All required gates passed. Ready for next step?"
header:   "Next"
options:
  - "Run /omh-check-pr for full audit" (Recommended) — description: "Verify PR fields + approvals"
  - "Exit — Tech Lead will merge" — description: "Close skill"
```

**If still running**:
```
question: "N gates still running. Wait or check later?"
header:   "Pending"
options:
  - "Check back manually" (Recommended) — description: "Exit skill"
  - "Print /loop command" — description: "Show /loop 2m /omh-ci-status for polling"
```

### Step 7 — Optional: fetch failed log tail

If user picked "Open failed job log(s)", for each failed gate:

**GitHub**:
```bash
gh run view <run-id> --log-failed --job <job-id> 2>&1 | tail -50
```

**Bitbucket**:
```
mcp__bitbucket__getPipelineStepLogs(..., pipeline_uuid=<uuid>, step_uuid=<step>)
```

Print the last 50 lines to help user diagnose without opening browser.

### Step 8 — Report

- **PR/Branch**: `<ref>`
- **Commit**: `<sha>`
- **Required gates**: X/Y passed, Z failed, W pending
- **Coverage**: X% (threshold 70%)
- **Overall**: READY / BLOCKED / PENDING
- **Next command**: `/omh-check-pr` (if ready) or manual fix

---

## Hard refusals

- Do NOT bypass or mark failed gate as "passed" — per §15 non-bypassable
- Do NOT approve skipping flaky tests without documenting (flaky policy needs written justification + TL approval)
- Do NOT modify CI configs — this is read-only monitoring
- Do NOT re-run passing checks to "refresh" — wastes CI time

---

## What this skill does NOT do

- Does not poll continuously — user invokes `/loop 2m /omh-ci-status` for polling
- Does not merge PR (§15 — Tech Lead after all gates green)
- Does not edit CI config files
- Does not run CI locally
- Does not replace `/omh-check-pr` — this skill is CI-only; check-pr is the full §13 + §15 scorecard

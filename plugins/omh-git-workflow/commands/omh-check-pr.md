# Check PR readiness (OMH Git Strategy §13, §15)

**Usage**: `/omh-check-pr [pr-number-or-url]`

Examples:
- `/omh-check-pr` — validate the PR for current branch (auto-detect)
- `/omh-check-pr 4821` — validate a specific PR by number
- `/omh-check-pr https://github.com/org/repo/pull/4821` — from URL

Parse arguments from: $ARGUMENTS
- Optional: PR number or PR URL

---

## Rules (from README §13 Required PR Fields + §15 PR Policy + §15 CI Enforcement)

**Mandatory PR fields** (any missing = auto-reject per §13):

| Field | Required for | Notes |
|---|---|---|
| Title (conventional commit format) | All | `<type>(<scope>): <subject>` |
| Summary | All | 2–5 sentences, what + why |
| Changed files / components | All | Grouped by service/module |
| Test evidence | All | Screenshots, CI link, manual steps, or "pending + TL sign-off" |
| Risk level | All | Low / Medium / High |
| Jira ticket | All | Linked key in branch name or PR body |
| Rebase confirmation | All | Branch rebased onto latest master |
| Rollback plan | High-risk | Required when risk = High |
| Migration notes | DB/infra | For schema/index/infra changes |

**CI gates** (per §15 CI Enforcement):
- Build
- Unit tests (≥70% coverage)
- Lint / static analysis
- SonarQube quality gate
- AI code review (non-blocking but flagged High findings must be addressed)

**Approvals** (per §15):
- Work branch → master: 2 approvals (must include Tech Lead)
- Hotfix → master: 1 approval (must be Tech Lead)

**Rebase status**: zero conflicts against master required (§15).

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended. Bundle independent questions (max 4).

---

## Workflow

### Step 1 — Identify PR

If PR number/URL provided → use it.

Otherwise detect from current branch:
```bash
git branch --show-current
git config --get remote.origin.url
```

- GitHub: `gh pr view --json number,url,state,isDraft,baseRefName,headRefName,title,body,author,reviewRequests,reviews,mergeable,mergeStateStatus,statusCheckRollup`
- Bitbucket: `mcp__bitbucket__getPullRequest(workspace, repo_slug, pull_request_id)` — use `mcp__bitbucket__getPullRequests` with filter if PR number unknown

If no PR exists for current branch → report: *"No PR found for branch `<branch>`. Use `/omh-open-pr` to create one."*

### Step 2 — Field-by-field audit

For each of the 8 mandatory fields, check presence:

| Check | Pass criterion |
|---|---|
| **Title format** | Matches `^(feat|fix|refactor|infra|hotfix|docs|test|other)(\([a-z-]+\))?: .+` |
| **Subject length** | `<type>(<scope>): <subject>` total ≤50 chars per §14 |
| **Summary** | Body has `## Summary` section with ≥2 sentences, not empty/placeholder |
| **Changed files** | Body has `## Changed files / components` (or similar) with bullet list |
| **Test evidence** | Body has `## Test evidence` with at least one bullet (screenshot / URL / steps / "pending") |
| **Risk level** | Body explicitly states `Low`, `Medium`, or `High` |
| **Jira ticket** | Body has `Refs: <KEY>` OR branch name contains `[A-Z]+-[0-9]+` |
| **Rebase confirmation** | Body has "rebased onto master" statement AND `git rev-list --count HEAD..origin/master == 0` |

Plus conditional checks:
- If risk = High → body must contain `## Rollback plan` section with non-empty content
- If diff touches `*.sql` / `migrations/` / `infra/` / CI configs → body must contain `## Migration notes`

### Step 3 — CI status

Fetch current CI status:
- GitHub: `gh pr checks <pr>` (output shows each check)
- Bitbucket: `mcp__bitbucket__getPullRequestStatuses`

Map to the required CI gates:
- Build ✅/❌
- Unit tests ✅/❌ (check coverage ≥70% if coverage report available)
- Lint ✅/❌
- SonarQube gate ✅/❌
- AI review — list High-severity findings if any

### Step 4 — Approvals

- GitHub: list reviewers + approval states from `gh pr view --json reviews`
- Bitbucket: `mcp__bitbucket__getPullRequestActivity`

Check:
- Work branch → master: ≥2 approvals AND at least one from Tech Lead
- Hotfix → master: ≥1 approval from Tech Lead

The skill does not know who the Tech Lead is — ask user to confirm if ambiguous:
```
AskUserQuestion:
  question: "Which reviewer(s) is the Tech Lead?"
  header:   "Tech Lead"
  multiSelect: true
  options:
    - "<reviewer-1>" — description: "Approved ✅" or "Pending"
    - "<reviewer-2>" — description: "..."
    - "<reviewer-3>" — description: "..."
    - "Tech Lead not among reviewers" — description: "Need to request review"
```

### Step 5 — Rebase status

```bash
git fetch origin master
git rev-list --count HEAD..origin/master    # how many commits behind master
```

If > 0 → rebase needed.

### Step 6 — Summary report

Print a structured scorecard:

```
PR #<N>: <title>
Branch: <head> → <base>
Author: <author>
Status: <OPEN|DRAFT|MERGED|CLOSED>

┌─ Required fields ─────────────────────────┐
│ ✅ Title format (conventional commit)     │
│ ✅ Subject length (42/50)                 │
│ ❌ Summary — missing or <2 sentences      │
│ ✅ Changed files listed                   │
│ ⚠️ Test evidence — marked pending         │
│ ✅ Risk level: Medium                     │
│ ✅ Jira: ELS-123                          │
│ ❌ Rebase — 3 commits behind master       │
│ n/a Rollback plan (not High risk)         │
│ n/a Migration notes (no DB/infra diff)    │
└───────────────────────────────────────────┘

┌─ CI gates ────────────────────────────────┐
│ ✅ Build                                   │
│ ❌ Unit tests — coverage 67% (<70%)       │
│ ✅ Lint                                    │
│ ⏳ SonarQube running                       │
│ ⚠️ AI review — 1 High severity finding   │
└───────────────────────────────────────────┘

┌─ Approvals (need 2, including Tech Lead) ─┐
│ ✅ <reviewer-1> (Tech Lead)                │
│ ⏳ <reviewer-2> pending                     │
└───────────────────────────────────────────┘

Verdict: NOT READY TO MERGE
Blockers: summary missing, rebase needed, coverage below threshold, approval pending
```

### Step 7 — Offer actions

```
AskUserQuestion:
  question: "Blockers detected. What next?"
  header:   "Action"
  options:
    - "Add missing fields to PR body" (Recommended) — description: "Walk me through each missing field"
    - "Rebase onto master" — description: "Switch to branch, git rebase origin/master (conflicts manual)"
    - "Re-request review from Tech Lead" — description: "Print GitHub/Bitbucket request URL"
    - "Nothing — I'll fix manually" — description: "Close the skill"
```

If "Add missing fields", walk through each missing field via `AskUserQuestion` and finally offer to update the PR body via `gh pr edit` or `mcp__bitbucket__updatePullRequest`.

### Step 8 — If all checks pass

```
Verdict: READY TO MERGE

┌─ Required fields ────────── ALL ✅         │
│ CI gates ─────────────────── ALL ✅         │
│ Approvals ───────────────── COMPLETE ✅     │
│ Rebase ────────────────────── CLEAN ✅      │
└─────────────────────────────────────────────┘
```

Ask:
```
AskUserQuestion:
  question: "All checks pass. Merge now?"
  header:   "Merge"
  options:
    - "Not yet — Tech Lead finalizes" (Recommended) — description: "Per §15, Tech Lead is final approver"
    - "I'm Tech Lead — merge" — description: "Trigger merge via gh/Bitbucket API"
    - "Defer (will merge later)" — description: "Close skill"
```

Never auto-merge without explicit Tech Lead confirmation.

---

## Hard refusals

- Do NOT mark PR ready if rebase is not clean — §15 requires zero conflicts
- Do NOT approve Tech Lead absence — skill must flag if no TL among reviewers
- Do NOT merge without 2 approvals (or 1 for hotfix) — §15 rule
- Do NOT fabricate test evidence to fill in missing field — flag as "pending + TL sign-off" per §13

---

## What this skill does NOT do

- Does not run CI itself (CI runs on remote; skill only reads status)
- Does not auto-rebase (conflicts require manual resolution)
- Does not approve on behalf of Tech Lead
- Does not merge without final explicit confirmation (§15 Tech Lead gate)

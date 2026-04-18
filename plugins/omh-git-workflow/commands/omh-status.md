# Status Dashboard (OMH Git Strategy — cross-reference)

**Usage**: `/omh-status`

No arguments. Prints a single-screen dashboard of everything the user needs to decide "what do I do next?".

---

## What this skill prints

A single dashboard output with 6 sections:

1. **Current context** — branch, Jira key, behind/ahead master, dirty tree
2. **My open PRs** — title, state, CI status, rebase status
3. **Active releases** — `release/*` branches with owner
4. **Throwaway branch freshness** — develop / staging stale or current
5. **Stale work branches** — my branches ≥ 30 days old per §12
6. **Action suggestions** — next recommended `/omh-*` command

No user prompts unless ambiguity forces it. Read-only by design.

---

## Interaction convention

If user input is needed (e.g. multiple GitHub accounts detected), use `AskUserQuestion`. Otherwise run silently and print the dashboard.

---

## Workflow

### Step 1 — Gather data in parallel

```bash
git fetch origin --prune --tags
git branch --show-current
git status --porcelain
git rev-parse HEAD
git rev-list --count HEAD..origin/master
git rev-list --count origin/master..HEAD
git config --get remote.origin.url
git log -5 --oneline --decorate
```

Detect platform (GitHub vs Bitbucket) from remote URL.

### Step 2 — Section 1: Current context

Extract:
- Current branch
- Jira key from branch name (pattern `[A-Z]+-[0-9]+`)
- Behind/ahead master
- Dirty file count (max 3 filenames shown)
- Latest commit SHA short

If Jira key detected, call `mcp__mcp-atlassian__jira_get_issue(issue_key)` to fetch summary + status. Fail silently if MCP not available.

Example output:
```
┌─ Current ────────────────────────────────────────┐
│ Branch:   ELS-1001-add-plugin-install-quickstart │
│ Jira:     ELS-1001 (In Progress) — Create docs…  │
│ HEAD:     3282481                                 │
│ vs master: 1 ahead, 0 behind  ✅                  │
│ Tree:     clean                                   │
└──────────────────────────────────────────────────┘
```

### Step 3 — Section 2: My open PRs

**GitHub**:
```bash
gh pr list --author @me --state open --json number,title,url,baseRefName,headRefName,mergeStateStatus,statusCheckRollup,reviews --limit 10
```

**Bitbucket**:
```
mcp__bitbucket__getPullRequests(..., query="state=OPEN AND author.account_id=<me>")
```

For each PR, compute:
- Title (truncate to 50 chars)
- Base → head
- CI status summary: ✅ all pass | ❌ N failed | ⏳ running | ⏸ none
- Approval count

If 0 open PRs → print "No open PRs authored by you."

### Step 4 — Section 3: Active releases

```bash
git branch -r | grep 'origin/release/' | sed 's|.*origin/||'
```

For each release branch:
- Last commit date + author
- Check if any tag points at it already (= likely deployed, should be cleaned up)

If 0 release branches → print "No active releases."

### Step 5 — Section 4: Throwaway branch freshness

```bash
# How old is develop/staging compared to master?
git log --format='%ct' origin/develop -1
git log --format='%ct' origin/master -1
git rev-list --count origin/develop..origin/master    # master commits develop doesn't have
git rev-list --count origin/staging..origin/master
```

For develop:
- If 0 commits behind master → "✅ develop is current"
- If 1–10 commits behind → "⚠ develop is N commits stale — consider `/omh-reset-develop`"
- If > 10 → "🔴 develop is very stale (N commits) — `/omh-reset-develop` overdue"

Same logic for staging.

### Step 6 — Section 5: Stale work branches

```bash
# My branches (heuristic: last author email match) older than 30 days
for branch in $(git branch -r | grep -E 'origin/[A-Z]+-[0-9]+' | sed 's|.*origin/||'); do
  age_days=$(( ($(date +%s) - $(git log -1 --format=%ct origin/$branch)) / 86400 ))
  author=$(git log -1 --format=%ae origin/$branch)
  if [ "$age_days" -ge 30 ] && [ "$author" = "$(git config user.email)" ]; then
    echo "$branch  $age_days days"
  fi
done
```

Per §12: "Stale work branches (no commits for 30+ days) must be reviewed and either closed or rebased."

If none → omit this section.

### Step 7 — Section 6: Suggested next action

Decision tree based on current state:

| State | Suggestion |
|---|---|
| On master, no open PRs | `/omh-new-branch <JIRA-KEY>` to start new work |
| On master, develop stale | `/omh-reset-develop` (if Tech Lead) |
| On work branch, dirty tree | `/omh-commit` to save progress |
| On work branch, clean + behind master | `/omh-sync-master` to rebase |
| On work branch, clean + ahead of master, no PR | `/omh-open-pr` |
| On work branch, PR open, CI running | "⏳ Wait for CI — then `/omh-check-pr`" |
| On work branch, PR approved | "✅ Ready to merge — Tech Lead should squash" |
| On release branch + QA pending | `/omh-reset-staging release <branch>` |
| Merged PR, still on branch | `/omh-delete-branch` |

Pick the single highest-priority suggestion and print it. Don't flood the user with options.

### Step 8 — Print dashboard

Assemble all sections into a single printed block. Use ASCII box-drawing for visual grouping.

Full example output:
```
╔═══════════════════════════════════════════════════╗
║  OMH Status — 2026-04-18 17:22                    ║
╚═══════════════════════════════════════════════════╝

┌─ Current ──────────────────────────────────────────┐
│ Branch:    ELS-1001-add-plugin-install-quickstart  │
│ Jira:      ELS-1001 · In Progress · Tom            │
│ HEAD:      3282481                                 │
│ vs master: 1 ahead, 0 behind   ✅                  │
│ Tree:      clean                                   │
└────────────────────────────────────────────────────┘

┌─ My open PRs (1) ──────────────────────────────────┐
│ #2  docs(plugin): add plugin install quickstart..  │
│     master ← ELS-1001-add-plugin-install-quicks..  │
│     CI: ⏸ none · Reviews: 0/2                       │
└────────────────────────────────────────────────────┘

┌─ Active releases ──────────────────────────────────┐
│ None                                                │
└────────────────────────────────────────────────────┘

┌─ Throwaway freshness ──────────────────────────────┐
│ develop:  🔴 3 commits behind master — reset soon  │
│ staging:  🔴 3 commits behind master — reset soon  │
└────────────────────────────────────────────────────┘

┌─ Stale work branches (you) ────────────────────────┐
│ INFRA-001-fix-plugin-schema     2 days (merged)    │
└────────────────────────────────────────────────────┘

💡 Next: /omh-check-pr 2  (audit PR #2 readiness)
```

### Step 9 — Exit

Pure read-only skill — no prompts unless needed. User runs any `/omh-*` command from the suggestion themselves.

---

## Hard refusals

- Do NOT modify any branch, tag, or remote state
- Do NOT auto-execute the suggested next action
- Do NOT block on slow MCP calls — if Jira MCP takes > 3s, print the Jira key only and continue

---

## What this skill does NOT do

- Does not automatically run any of the suggested commands
- Does not list other team members' branches or PRs (self-focused)
- Does not replace `/omh-check-pr` — this is a snapshot, that one is a detailed audit
- Does not track Jira board state beyond the single ticket in the current branch name

# Assign Reviewers (OMH Git Strategy §15 Tech Lead Policy)

**Usage**: `/omh-reviewers [pr-number]`

Examples:
- `/omh-reviewers` — assign reviewers to current branch's PR
- `/omh-reviewers 42` — assign to PR #42

Parse arguments from: $ARGUMENTS
- Optional: PR number

---

## Rules (from README §15 PR Policy + §15 Tech Lead Involvement Policy)

**Approval requirements**:
- Work branch → master: **2 approvals (must include Tech Lead)**
- Hotfix → master: **1 approval (must be Tech Lead)**
- develop merges: no PR, no approval needed (§6)

**Tech Lead is required approver, not optional reviewer** (§15) — cannot merge without TL approval or documented delegation.

**High-risk PRs** (per §13 risk level): TL must review and sign off on rollback plan BEFORE any other review begins.

---

## Configuration

Reviewer mapping comes from a team-level config file `.claude/omh-reviewers.yml` in the repo root. Format:

```yaml
# .claude/omh-reviewers.yml
tech_leads:
  - github-username: alice-tl
  - github-username: bob-tl

# Domain experts by scope (§14 scope list)
domain_experts:
  auth:
    - charlie-auth
    - dave-auth
  payment:
    - eve-payment
  booking:
    - frank-booking
  search:
    - grace-search
  infra:
    - henry-devops
  ui:
    - ivy-frontend
  api:
    - jack-backend
  notification:
    - kate-notifs

# Fallback when no domain expert matches
default_reviewers:
  - leo-senior
```

If the config file doesn't exist → stop with: *"No `.claude/omh-reviewers.yml` found. Create one at repo root (see skill docs for template) or assign reviewers manually."*

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended.

---

## Workflow

### Step 1 — Resolve PR

If `$ARGUMENTS` gives a PR number, use it. Otherwise auto-detect from current branch via `gh pr view` / `mcp__bitbucket__getPullRequests`.

If no PR found → stop with: *"No PR found for branch. Use `/omh-open-pr` first."*

### Step 2 — Read config

```bash
cat .claude/omh-reviewers.yml
```

Parse YAML. If schema invalid or missing required keys (`tech_leads`) → stop with error.

### Step 3 — Classify the PR

Determine PR type from branch name:
- `hotfix/{JIRA-KEY}-*` → **hotfix PR** → needs 1 TL
- `{JIRA-KEY}-*` → **work branch PR** → needs 2 approvals incl. TL

Check existing reviewers (`gh pr view --json reviewRequests,reviews`):
- List who's already requested/approved
- Determine if TL is among them

### Step 4 — Identify scope from diff

Map changed files to scopes (§14 list):
```bash
gh pr diff <N> --name-only
# or: git diff --name-only origin/master...HEAD
```

Infer scope:
- `auth/*`, `authentication/*`, `login*` → `auth`
- `payment*`, `billing*`, `checkout*` → `payment`
- `booking*`, `reservation*` → `booking`
- `search*`, `filter*` → `search`
- `infra*`, `deploy*`, `ci/*`, `.github/workflows/*` → `infra`
- `frontend*`, `ui/*`, `components/*`, `*.tsx`, `*.vue` → `ui`
- `api/*`, `backend/*`, `controllers/*`, `handlers/*` → `api`
- `notification*`, `email*`, `push*` → `notification`

If multiple scopes touched → pick all matching domain experts (dedup).

### Step 5 — Propose reviewer list

Algorithm:
1. **Always include 1 Tech Lead** from `tech_leads` — pick one who's not already the PR author
2. **For work branch PRs (need 2 approvals)**: add 1 domain expert based on scope
3. **For hotfix PRs (need 1 TL only)**: skip domain expert unless user wants extra
4. **Exclude the PR author** from all lists
5. **Exclude already-requested reviewers** from the proposal (they're already there)

If no domain expert matches scope → fall back to `default_reviewers`.

### Step 6 — Confirm via AskUserQuestion

Show the proposed list and let user confirm/override. For work branch PR (2 approvals):

```
AskUserQuestion:
  question: "Propose reviewers for PR #N (<branch>, scope: <scope>):"
  header:   "Reviewers"
  multiSelect: true
  options:
    - "Tech Lead: <tl-name>" (Recommended) — description: "Required per §15"
    - "Domain expert: <expert>" (Recommended) — description: "Matches scope <scope> from diff"
    - "Second TL (if primary unavailable)" — description: "Backup Tech Lead"
    - "Default fallback: <leo>" — description: "Senior reviewer when no domain match"
```

For hotfix PR (1 TL):
```
AskUserQuestion:
  question: "Select Tech Lead reviewer for hotfix PR #N:"
  header:   "TL pick"
  multiSelect: false
  options:
    - "<tl-1>" (Recommended) — description: "Primary on-call Tech Lead"
    - "<tl-2>" — description: "Alternate Tech Lead"
    - "I'll pick via Other" — description: "Type username"
```

### Step 7 — Request reviews

**GitHub**:
```bash
gh pr edit <N> --add-reviewer <user-1>,<user-2>
```

**Bitbucket**:
```
mcp__bitbucket__updatePullRequest(
  ..., pull_request_id=<N>,
  reviewers=[{"username": "<user-1>"}, {"username": "<user-2>"}]
)
```

If request fails (invalid username, already requested, user is author) → surface error and skip that user.

### Step 8 — Notify (optional)

```
AskUserQuestion:
  question: "Reviewers requested. Post announcement in team channel?"
  header:   "Notify"
  multiSelect: false
  options:
    - "Skip — GitHub notifies them" (Recommended) — description: "Default GitHub email/UI notification is enough"
    - "Print Slack message template" — description: "Template I can copy-paste to manually ping"
```

If user picks "Print template", show:
```
@<tl-handle> @<expert-handle>
PR #N needs your review:
<pr-url>

Summary: <first line of PR summary>
Risk: <level>

Per §15 this needs <X> approvals (incl. Tech Lead) to merge.
```

### Step 9 — Special case: High-risk PR

If PR risk level = High (from body parse):
- Tech Lead MUST review first before any other review (§15)
- Print warning:
  ```
  ⚠ This is a High-risk PR. Per §15:
    - Tech Lead must review and sign off on rollback plan first
    - Other reviewers should wait until TL has acknowledged
    - Skill only requests TL now; add other reviewers after TL signs off
  ```
- Only request TL at this step. User re-runs after TL sign-off to add domain expert.

### Step 10 — Report

- **PR**: #N · `<branch>`
- **Type**: work branch / hotfix
- **Scope detected**: `<scope>`
- **Requested reviewers**: `<list>`
- **Approvals needed**: 2 (incl. TL) or 1 (TL only)
- **Currently approved**: <count>
- **Next**: wait for reviews; use `/omh-ci-status` in parallel

---

## Hard refusals

- Do NOT request review from PR author (self-review not allowed)
- Do NOT skip Tech Lead — all PRs to master need TL per §15
- Do NOT request > 4 reviewers (review fatigue; keeps review focused)
- Do NOT auto-approve on behalf of anyone
- Do NOT merge — TL handles after approvals

---

## Config file auto-creation

If `.claude/omh-reviewers.yml` doesn't exist, offer to create a template:

```
AskUserQuestion:
  question: "No reviewer config found. Create .claude/omh-reviewers.yml template?"
  header:   "Config"
  options:
    - "Create template" (Recommended) — description: "I'll create a skeleton; you fill in usernames then commit"
    - "Cancel" — description: "I'll create it manually"
```

Template content (commented, so the skill fails loud until user fills in real data):
```yaml
# Reviewer mapping for /omh-reviewers skill
# Fill in GitHub/Bitbucket usernames, then commit to repo

tech_leads:
  # - github-username: REPLACE_WITH_TL_USERNAME

domain_experts:
  auth: []
  payment: []
  search: []
  booking: []
  infra: []
  ui: []
  api: []
  notification: []

default_reviewers:
  # - REPLACE_WITH_SENIOR_USERNAME
```

---

## What this skill does NOT do

- Does not approve reviews — reviewers do that themselves
- Does not request review from Claude or automated bots (always human reviewers per §15)
- Does not merge PR (Tech Lead after approvals)
- Does not maintain the config file (team-owned, committed to repo)

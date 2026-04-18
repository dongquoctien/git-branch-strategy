# Open Pull Request to master (OMH Git Strategy §13, §15)

**Usage**: `/omh-open-pr [target-branch]`

Example: `/omh-open-pr` (defaults to `master`)

Parse arguments from: $ARGUMENTS
- Optional: target branch (default `master`)

---

## Rules (from README §13 PR Standards + §15 PR Policy)

**All PR fields are MANDATORY — reviewers must reject PRs missing any field.**

| Field | Required | Notes |
|---|---|---|
| Title | Always | Format: `<type>(scope): description` — conventional commit |
| Summary | Always | 2–5 sentences, what changed and WHY (not how) |
| Changed files / components | Always | List affected services/modules |
| Test evidence | Always | Screenshots, test output, or manual steps |
| Risk level | Always | Low / Medium / High |
| Jira ticket(s) | Always | Linked ticket — PR blocks without it |
| Rebase confirmation | Always | Branch must be rebased onto latest master |
| Rollback plan | High risk only | Required when risk = High |
| Migration notes | DB/infra only | For schema/index/infra changes |

**Approval requirements:**
- Work branch → master: 2 approvals (must include Tech Lead)
- Hotfix → master: 1 approval (must be Tech Lead)
- develop: no PR required (direct merge per §6)

**Hard gates before merge:** Build, Unit tests (≥70% coverage), Lint, SonarQube gate.

---

## Workflow

### Step 1 — Inspect branch state

Run in parallel:
```bash
git branch --show-current
git status --porcelain
git log origin/master..HEAD --oneline
git diff origin/master...HEAD --stat
git fetch origin master
git rev-list --count HEAD..origin/master
```

Checks:
- Current branch is NOT `master`, `develop`, `staging`, `release/*` — if it is, stop
- Working tree is clean — if not, stop, tell user to commit first
- Branch has at least 1 commit ahead of master — if 0, stop, "nothing to PR"
- Branch name matches `{JIRA-KEY}-*` or `hotfix/{JIRA-KEY}-*` — else warn

Extract:
- Jira key from branch name
- Commit list (for summary generation)
- Files changed (for "changed components" field)

### Step 2 — Verify rebase status

```bash
git rev-list --count HEAD..origin/master
```

- If count > 0 → branch is behind master. **Stop** and tell user:
  > "Branch is N commits behind master. Rebase first: `git rebase origin/master`, resolve conflicts, then re-run."
- Do NOT auto-rebase (may have conflicts).

### Step 3 — Fetch Jira ticket details

```
mcp__mcp-atlassian__jira_get_issue(issue_key=<extracted-key>)
```

Extract:
- Summary (for PR title suggestion)
- Issue type → maps to commit type: Bug → `fix`, Story/Task → `feat`, Improvement → `refactor`
- Description (for PR summary context)

If no Jira key in branch name or ticket not found → stop, ask user to provide ticket.

### Step 4 — Derive PR fields

**Title** — conventional commit format:
- Use the type of the most recent commit, OR derive from Jira issue type
- Scope = primary touched module (see §14 scope list: `auth`, `payment`, `search`, `booking`, `infra`, `ui`, `api`, `notification`)
- Subject from Jira summary, rewritten in imperative mood, lowercase, no trailing period
- Example: `feat(auth): add Google OAuth login`

**Summary** (2–5 sentences):
- What changed + why (business impact / user-facing reason)
- Reference the Jira ticket context
- Do NOT explain how the code works

**Changed files / components**:
- Group files by service/module
- Format: `- <service>: <files or component names>`

**Test evidence** — call `AskUserQuestion` (do NOT ask open-ended):

```
AskUserQuestion:
  question: "What test evidence do you have? (mandatory per §13)"
  header:   "Test evid"
  multiSelect: true
  options:
    - label: "Unit test output" (Recommended) — description: "I run the test suite now and capture output"
    - label: "CI build link" — description: "Paste URL via Other"
    - label: "Manual test steps" — description: "Describe steps taken (Other for free-text)"
    - label: "Screenshots" — description: "Paste paths or drop into chat after"
```

Note: if user picks nothing / only "Other: none available" → flag the PR body as *"⚠️ Test evidence: pending — requires Tech Lead sign-off per §13"*. Never fabricate evidence.

**Risk level** — infer a default, confirm via `AskUserQuestion`:

Print the inferred level and reason first (e.g. *"Inferred: Medium — touches shared `auth/` utilities"*), then:

```
AskUserQuestion:
  question: "Confirm risk level"
  header:   "Risk"
  multiSelect: false
  options:
    - label: "Keep inferred (<X>)" (Recommended) — description: "Use the auto-inferred level"
    - label: "Low" — description: "Isolated, single module, easily reverted"
    - label: "Medium" — description: "Shared utilities, multiple modules, external deps"
    - label: "High" — description: "Cross-service, DB migration, auth/payment/booking core — requires rollback plan"
```

- **Low**: single module, no shared deps, easily revertible
- **Medium**: touches shared utilities, multiple modules, external service calls
- **High**: cross-service, DB migration, auth/payment/booking core, or hard to revert

Triggers for High automatically:
- Any file in `auth/`, `payment/`, `booking/` critical paths
- Any `*.sql`, migration files, schema changes
- Any change in `infra/`, CI/CD configs
- Dependency version bumps on core libs

**Rollback plan** (if High): ask user to describe how to revert. Do NOT auto-generate.

**Migration notes** (if DB/infra): ask user for:
- Estimated run time
- Zero-downtime status
- Rollback SQL / procedure

### Step 5 — Show PR preview & confirm via AskUserQuestion

Print the full PR body first as a readable block:
```
──────────────────────────────────────
Title:  <title>
Target: <branch>  |  Source: <branch>
Risk:   <Low|Medium|High>
──────────────────────────────────────
<body preview>
──────────────────────────────────────
```

Then call `AskUserQuestion`:

```
AskUserQuestion:
  question: "Create this PR?"
  header:   "Create PR"
  multiSelect: false
  options:
    - label: "Create as shown" (Recommended) — description: "Push branch and open PR now"
    - label: "Edit title/summary" — description: "Revise PR title or summary text"
    - label: "Change risk or add plan" — description: "Change risk level or add rollback/migration notes"
    - label: "Cancel" — description: "Don't create PR"
```

Handle the sub-flows:
- **Edit title/summary** → `AskUserQuestion` with options `["Title", "Summary", "Both"]`, then free-text via Other
- **Change risk or add plan** → `AskUserQuestion` with options `["Risk level", "Rollback plan", "Migration notes", "All of these"]`
- Always re-show preview and re-prompt until user picks "Create as shown" or "Cancel"

Template:
```markdown
## Summary
<2–5 sentences>

## Changed files / components
- <service>: <components>

## Jira
<JIRA-KEY>: <ticket-summary-link>

## Test evidence
<screenshots / test output / manual steps>

## Risk level
<Low | Medium | High> — <justification>

## Rebase confirmation
✅ Branch rebased onto latest master as of <YYYY-MM-DD>

<!-- High-risk PRs only -->
## Rollback plan
<how to revert>

<!-- DB/infra changes only -->
## Migration notes
- Estimated run time: <X>
- Zero-downtime: <yes/no>
- Rollback: <SQL or procedure>
```

### Step 6 — Push branch

```bash
git push -u origin <branch-name>
```

- If branch already pushed and diverged → ask user. Do NOT auto force-push.
- If up-to-date → skip push, proceed.

### Step 7 — Create the PR

**Detect remote** (Bitbucket vs GitHub) from `git remote get-url origin`:

**Bitbucket (ohmyhotel workspace):**
```
mcp__bitbucket__createPullRequest(
  workspace="ohmyhotel",
  repo_slug=<repo>,
  title=<title>,
  sourceBranch=<current-branch>,
  targetBranch=<target>,
  description=<body>
)
```

**GitHub:**
```bash
gh pr create --base <target> --head <branch> --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

### Step 8 — Link PR back to Jira

```
mcp__mcp-atlassian__jira_add_comment(
  issue_key=<jira-key>,
  comment="PR opened: <pr-url>"
)
```

### Step 9 — Report

Output:
- **Branch**: `<branch-name>`
- **Target**: `<target-branch>`
- **Title**: `<pr-title>`
- **Risk**: Low / Medium / High
- **PR URL**: `<url>`
- **Reviewers needed**: 2 approvals (must include Tech Lead) for master; 1 for hotfix
- **CI gates**: Build, Unit tests ≥70%, Lint, SonarQube — all must pass before merge

---

## Interaction convention — ALWAYS use AskUserQuestion

Do NOT print numbered text options. Every prompt uses the `AskUserQuestion` tool so the user clicks / arrow-keys to select.

Rules:
- `header`: ≤12 chars chip label
- 2–4 options; first option is safest/recommended (suffix `" (Recommended)"`)
- Do NOT add "Other" — tool adds it automatically for free-text
- Destructive options last, description starts with `"IRREVERSIBLE: "`
- Bundle independent questions in one call (max 4) so user answers in one UI pass

## Error handling

- **Branch not pushed yet**: push first with `-u`
- **PR already exists for branch**: fetch existing PR, offer to update description
- **MCP Bitbucket/GitHub unavailable**: fall back to `gh` CLI (GitHub) or output the PR body and ask user to create manually
- **Jira ticket closed**: warn — should this PR exist?
- **Target branch is develop/staging**: refuse — per §15, PR to master only. Direct merge to develop doesn't need PR.

---

## Hard refusals

- Do NOT open PR targeting `develop` or `staging` (no PR required per §15; direct merge only)
- Do NOT open PR from `master` / `develop` / `staging` / `release/*` as source
- Do NOT bypass the rebase check — per §15 "zero conflicts required"
- Do NOT fabricate test evidence — flag as pending if missing

---

## What this skill does NOT do

- Does not auto-rebase (user must rebase manually to handle conflicts)
- Does not run CI locally (CI runs on the remote after push)
- Does not approve or merge (that's reviewer + Tech Lead)
- Does not handle hotfix-specific flow (use `/omh-hotfix` — different branch source and 1-approval rule)

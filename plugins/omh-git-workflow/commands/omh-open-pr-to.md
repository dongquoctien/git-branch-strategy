# Open Pull Request to a Specified Branch (OMH Git Strategy §6, §8, §9, §13)

**Usage**: `/omh-open-pr-to <target-branch>`

Examples:
- `/omh-open-pr-to staging` — PR into staging (skill asks for the §8/§9 purpose)
- `/omh-open-pr-to ELS-234-add-dark-mode` — PR from a personal sub-branch into the ticket's main work branch (§6 step 2)
- `/omh-open-pr-to develop` — refused (§6: direct merge, no PR)
- `/omh-open-pr-to release/v1.4.0-payment` — refused (§9: use `/omh-cherry-pick`)
- `/omh-open-pr-to master` — redirects to `/omh-open-pr` (§15 standard flow)

Parse arguments from: $ARGUMENTS
- Required: target branch. If omitted → `AskUserQuestion` to pick.

---

## Why this skill exists (vs `/omh-open-pr`)

`/omh-open-pr` is the **standard §15 flow**: work-branch → master, 2 approvals incl. Tech Lead, rebase strict. This skill handles **every other valid PR target** that the strategy doc allows but `/omh-open-pr` refuses:

- `staging` (pre-release feature test §8.1, or final deploy verification §8.2)
- another work branch (sub-branch → ticket's main work branch, §6 step 2)

And it explicitly **refuses** the forbidden targets (`develop`, `release/*`) with a pointer to the correct skill, so engineers don't bypass the strategy by accident.

---

## Rules (from README §6 develop, §8 staging, §9 bugfix-during-release, §13 PR Standards)

**PR body fields are MANDATORY (§13) for every target. Reviewers must reject PRs missing any field.**

| Field | Required | Notes |
|---|---|---|
| Title | Always | Conventional: `<type>(scope): description` |
| Summary | Always | 2–5 sentences, what + WHY (not how) |
| Changed files / components | Always | Group by service/module |
| Test evidence | Always | Screenshots, test output, or manual steps |
| Risk level | Always | Low / Medium / High |
| Jira ticket(s) | Always | Linked ticket — PR blocks without it |
| Rebase confirmation | Always | Branch rebased onto **master** (§3/§6 — work branches stay master-based, never rebased onto target) |
| Promotion path | Opt-in | Per §4 — helps reviewer place the PR in the release chain |
| Rollback plan | High risk only | Required when risk = High |
| Migration notes | DB/infra only | For schema/index/infra changes |

**Approval requirement is computed per target** (no hard-coded "2 + Tech Lead" for non-master):

| Target | Approvals |
|---|---|
| `staging` — pre-release feature test (§8.1) | 1 approval (QA or Tech Lead) |
| `staging` — final deploy verification (§8.2) | Tech Lead sign-off |
| work branch (sub-branch → main work branch, §6 step 2) | Team norm (not strategy-mandated) |

**Hard gates before merge** still apply per §15: Build, Unit tests (≥70%), Lint, SonarQube — regardless of target.

---

## Want to test your branch on develop or staging env? (§6, §8)

A common ask: *"My branch was cut from master, I just want to deploy it to the develop/staging env to test."* The strategy doc handles this via **direct merge into the throwaway branch**, not via PR. The key insight: your branch stays clean — only the throwaway branch (`develop` / `staging`) gets the merged code, and it will be reset back to master at the next deploy cycle (§6, §8). Your work branch is untouched.

### Test on develop (§6 — no PR required)

```bash
# Your work branch (cut from master) stays untouched.
# develop is throwaway — merge your branch INTO develop, never the other way.
git checkout develop
git fetch origin
git reset --hard origin/develop          # if local develop is stale
git merge --no-ff <your-branch>          # merge your work into develop
git push origin develop                   # deploys to develop env
git checkout <your-branch>                # back to your branch, unchanged
```

If multiple devs are doing this concurrently and develop drifts, Tech Lead resets develop via `/omh-reset-develop` (§6). No back-merge is needed because develop syncs to master via periodic reset (§3).

### Test on staging — pre-release feature test (§8.1)

This is where `/omh-open-pr-to staging` IS the right command: a single feature gets tested on staging via PR. Source = your `{JIRA-KEY}-*` branch (master-based, never rebased onto staging). Approval: 1 (QA or Tech Lead).

### Why never rebase your branch onto develop/staging

Your branch was cut from master and must STAY master-based. Rebasing it onto `develop` (which contains 30 other devs' WIP that hasn't reached master) pulls all that code into your branch:

- Your branch is no longer "independently deployable" (§3 broken)
- You inherit conflicts that aren't yours
- Landing your branch on master later would drag develop's code along — that's a `develop → master` reverse merge, **forbidden by §3**

The throwaway-branch model exists exactly so you can deploy-to-test without contaminating your source.

---

## Interaction convention — ALWAYS use AskUserQuestion

Do NOT print numbered text options. Every prompt uses `AskUserQuestion`.

Rules:
- `header`: ≤12 chars chip label
- 2–4 options; first option is safest/recommended (suffix `" (Recommended)"`)
- Do NOT add "Other" — the tool adds it automatically for free-text
- Destructive options last; description starts with `"IRREVERSIBLE: "`
- Bundle independent questions in one call (max 4)

---

## Workflow

### Step 1 — Resolve target & dispatch

Read `<target-branch>` from `$ARGUMENTS`. If missing, prompt:

```
AskUserQuestion:
  question: "Target branch for this PR?"
  header:   "Target"
  multiSelect: false
  options:
    - "staging" (Recommended) — description: "PR into staging — skill will ask the §8/§9 purpose"
    - "Another work branch" — description: "Sub-branch → ticket's main work branch (§6 step 2)"
    - "Cancel" — description: "Exit skill"
```

**Dispatch table — decide what to do with the target before doing anything else:**

| Target value | Action |
|---|---|
| `master` | **Redirect.** Print: *"Target `master` is the §15 standard flow — use `/omh-open-pr` instead. Exiting."* Stop. |
| `develop` | **Refuse (§6).** Print the test-on-develop block from the section below. Stop. |
| `release/*` (matches `release/v*`) | **Refuse + delegate (§9).** Print: *"§9 upstream-first: never PR into a release branch. Land the fix on master first via `/omh-open-pr`, then cherry-pick to release via `/omh-cherry-pick`."* Stop. |
| `staging` | Continue to Step 2 (staging-specific). |
| Anything else | Treat as **work branch target** — continue to Step 2 (work-branch path). If name doesn't match `{JIRA-KEY}-*`, warn but continue. |

### Step 2 — Inspect source branch state

Run in parallel:
```bash
git branch --show-current
git status --porcelain
git fetch origin <target>
git log origin/<target>..HEAD --oneline
git diff origin/<target>...HEAD --stat
git rev-list --count HEAD..origin/<target>
```

Source checks:
- Source branch is NOT `master`, `develop`, `staging`, `release/*` — if it is, stop (per §6/§8: those are throwaway / release-only and never act as PR source)
- Working tree is clean — if not, stop, tell user to commit first
- Source has at least 1 commit ahead of target — if 0, stop with *"nothing to PR — `<source>` is not ahead of `<target>`"*
- Source branch name extracted for Jira key lookup (Step 4)

### Step 3 — Validate target-specific source rules

**If target = `staging`** — ask the §8/§9 purpose before going further:

```
AskUserQuestion:
  question: "Target = staging. What is this PR for? (§8/§9)"
  header:   "Staging mode"
  multiSelect: false
  options:
    - "Pre-release feature test (§8.1)" (Recommended)
        — description: "Source must be a {JIRA-KEY}-* work branch. Approval: 1 (QA or Tech Lead)."
    - "Final deployment verification (§8.2)"
        — description: "Source must be a release/* branch. Approval: Tech Lead sign-off."
    - "Bugfix during release QA"
        — description: "IRREVERSIBLE: skill will refuse. §9 upstream-first — fix on master first, then /omh-cherry-pick into release."
    - "Cancel"
```

Handle the answer:
- **Pre-release feature test** → enforce: source matches `{JIRA-KEY}-*` (the `omh-new-branch` convention). If source = `release/*` or `hotfix/*`, refuse: *"§8.1 expects a work branch. For release verification pick 'Final deployment verification' instead."*
- **Final deployment verification** → enforce: source matches `release/v*`. If not, refuse: *"§8.2 expects a `release/*` source. Cut a release branch via `/omh-release` first."*
- **Bugfix during release QA** → refuse with the §9 explanation and the exact command sequence:
  ```
  # 1. Land fix on master
  /omh-new-branch <JIRA-KEY>
  # (implement fix)
  /omh-commit
  /omh-open-pr
  # 2. After merge, cherry-pick to release
  /omh-cherry-pick <merge-sha> <release-branch>
  ```
  Stop.
- **Cancel** → stop.

**If target = a work branch** — confirm the §6 step 2 flow:

```
AskUserQuestion:
  question: "Target = <target> (work branch). Confirm the flow?"
  header:   "Sub-branch"
  multiSelect: false
  options:
    - "Sub-branch → main work branch (§6 step 2)" (Recommended)
        — description: "Personal sub-branch merges into the ticket's shared work branch. Approval per team norm."
    - "Cross-feature dependency"
        — description: "PR from feature A into feature B. Warn: increases drift risk vs master."
    - "Cancel"
```

If user picks **Cross-feature dependency**, print: *"Heads-up: PR'ing between two unrelated work branches makes both harder to rebase onto master. Per §6, consider merging A to master first, then rebasing B."* and ask once more to proceed or cancel.

### Step 4 — Verify source is up-to-date with MASTER (not the PR target)

**Critical rule (§3, §6):** the source branch was cut from master and must stay master-based. Rebasing source onto `develop`, `staging`, or another work branch would pollute it with code that hasn't reached master yet — breaking §3 "each feature independently deployable" and §6 "rebase onto latest master, then open PR". Reverse merges (`develop → master`, `staging → master`) are forbidden by §3.

So the rebase check runs against **`origin/master`**, regardless of PR target:

```bash
git fetch origin master
git rev-list --count HEAD..origin/master
```

- If count > 0 → source is behind master. **Stop**: *"Source is N commits behind master. Rebase first: `git rebase origin/master`, resolve conflicts, then re-run. Per §3/§6, work branches stay master-based — never rebase onto a non-master target."*
- Do NOT auto-rebase (per CLAUDE.md "No silent auto-fixes").

**Mergeability check against the target** (informational, not a hard stop):

```bash
git fetch origin <target>
git merge-tree --write-tree --merge-base=$(git merge-base HEAD origin/<target>) HEAD origin/<target> >/dev/null 2>&1
```

If `git merge-tree` reports conflicts, surface them as a warning in the preview block (Step 7) — but do NOT force the user to resolve them by rebasing source onto target. Reviewers / GitHub UI / target maintainer will surface conflicts on merge.

> **Why not rebase source onto target?** Example: your branch is `ELS-234-add-dark-mode`, cut from master. Target = `develop`, which contains 30 other devs' in-progress work that hasn't reached master. Rebasing your branch onto `develop` would pull all that code into your branch — your branch is no longer "sourced from master", you inherit conflicts that aren't yours, and you can't later land it on master without dragging develop's code along (a forbidden reverse merge per §3).

### Step 5 — Fetch Jira ticket details

Extract Jira key from source branch name (e.g. `ELS-234-add-dark-mode` → `ELS-234`).

```
mcp__mcp-atlassian__jira_get_issue(issue_key=<extracted-key>)
```

Extract:
- Summary (for title suggestion)
- Issue type → commit type (Bug → `fix`, Story/Task → `feat`, Improvement → `refactor`)
- Description (for summary context)

If no Jira key in source name or ticket not found → ask via `AskUserQuestion`:
```
question: "No Jira key in branch name. Provide one?"
header:   "Jira"
options:
  - "Enter key now" (Recommended) — description: "Type via Other"
  - "Proceed without Jira link" — description: "PR body will flag 'Jira: pending — requires manual link'"
  - "Cancel"
```

### Step 6 — Derive PR fields

**Title** — conventional commit format, same as `/omh-open-pr`:
- Use the type of the most recent commit on source, OR derive from Jira issue type
- Scope from §14 list (`auth`, `payment`, `search`, `booking`, `infra`, `ui`, `api`, `notification`)
- Subject from Jira summary, imperative mood, lowercase, no trailing period

**Summary** (2–5 sentences) — what + WHY, reference Jira context, do not explain how.

**Changed files / components** — group by service/module, format `- <service>: <files>`.

**Test evidence** (mandatory §13):

```
AskUserQuestion:
  question: "What test evidence do you have? (mandatory per §13)"
  header:   "Test evid"
  multiSelect: true
  options:
    - "Unit test output" (Recommended) — description: "Run suite now and capture output"
    - "CI build link" — description: "Paste URL via Other"
    - "Manual test steps" — description: "Describe via Other"
    - "Screenshots" — description: "Paste paths"
```

If user picks nothing / only "Other: none available" → body field becomes *"⚠️ Test evidence: pending — requires sign-off"*. Never fabricate.

**Risk level** — infer a default, confirm via `AskUserQuestion`.

Inference rules (different from `/omh-open-pr` because the target isn't production-path):
- Default for `staging` (feature test) → **Low** (not on release path)
- Default for `staging` (deploy verification) → **Medium** (this code will deploy)
- Default for work-branch target → **Low** (still many merges away from master)
- Auto-promote to **High** if files touch `auth/`, `payment/`, `booking/`, `*.sql`, migrations, `infra/`, CI configs, or core dep version bumps

```
AskUserQuestion:
  question: "Confirm risk level (inferred: <X>)"
  header:   "Risk"
  options:
    - "Keep inferred (<X>)" (Recommended)
    - "Low" — description: "Isolated, single module, easily reverted"
    - "Medium" — description: "Shared utilities, multiple modules, external deps"
    - "High" — description: "Cross-service, DB migration, auth/payment/booking core — requires rollback plan"
```

**Rollback plan** (only if High): ask user to describe — do NOT auto-generate.

**Migration notes** (DB/infra): ask for estimated run time, zero-downtime status, rollback SQL.

**Promotion path** (opt-in per §4):

```
AskUserQuestion:
  question: "Add a Promotion path field? (helps reviewer place PR in the §4 chain)"
  header:   "Promo path"
  multiSelect: false
  options:
    - "Yes, auto-suggest from §4" (Recommended) — description: "Skill fills based on target type"
    - "Yes, I'll write it" — description: "Free-text via Other"
    - "No" — description: "Omit the field"
```

Auto-suggest rules (per §4 release diagram):
- Target = `staging` (feature test) → `<source> → staging → master → release/* → PROD`
- Target = `staging` (deploy verification) → `release/* → staging → tag → PROD`
- Target = work branch → `<source> → <target> → master → release/* → PROD`

### Step 7 — Show PR preview & confirm

Print a readable preview block:
```
──────────────────────────────────────
Title:     <title>
Source:    <source-branch>  (rebased on master: ✅ | ❌ behind by N)
Target:    <target>
Mode:      <staging-feature-test | staging-deploy-verify | sub-branch | cross-feature>
Mergeable: <clean | conflicts in N files — surfaced by GitHub on merge>
Risk:      <Low|Medium|High>
Approval:  <computed approval line>
──────────────────────────────────────
<body preview>
──────────────────────────────────────
```

Then:
```
AskUserQuestion:
  question: "Create this PR?"
  header:   "Create PR"
  options:
    - "Create as shown" (Recommended) — description: "Push branch and open PR now"
    - "Edit title/summary" — description: "Revise title or summary text"
    - "Change risk or add plan" — description: "Change risk level, rollback, migration"
    - "Toggle Promotion path" — description: "Add/remove the §4 promotion line"
    - "Cancel" — description: "Don't create PR"
```

Sub-flows (looping until user picks "Create as shown" or "Cancel"):
- **Edit title/summary** → `AskUserQuestion` `["Title", "Summary", "Both"]`, free-text via Other
- **Change risk or add plan** → `AskUserQuestion` `["Risk level", "Rollback plan", "Migration notes", "All of these"]`
- **Toggle Promotion path** → re-run Step 6 Promotion path prompt
- After any edit, re-render the preview and re-ask.

Body template (variant fields included only when applicable):

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
✅ Branch rebased onto latest `master` as of <YYYY-MM-DD> (per §3/§6 — source stays master-based regardless of PR target)

<!-- Opt-in §4 -->
## Promotion path
<source> → <target> → ... → PROD

<!-- High-risk only -->
## Rollback plan
<how to revert>

<!-- DB/infra only -->
## Migration notes
- Estimated run time: <X>
- Zero-downtime: <yes/no>
- Rollback: <SQL or procedure>
```

### Step 8 — Push source branch

```bash
git push -u origin <source-branch>
```

- If already pushed and diverged → ask user. Do NOT auto force-push.
- If up-to-date → skip push, proceed.

### Step 9 — Create the PR

Detect remote from `git remote get-url origin`:

**Bitbucket (`ohmyhotel` workspace):**
```
mcp__bitbucket__createPullRequest(
  workspace="ohmyhotel",
  repo_slug=<repo>,
  title=<title>,
  sourceBranch=<source>,
  targetBranch=<target>,
  description=<body>
)
```

**GitHub:**
```bash
gh pr create --base <target> --head <source> --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

### Step 10 — Link PR to Jira

```
mcp__mcp-atlassian__jira_add_comment(
  issue_key=<jira-key>,
  comment="PR opened: <pr-url> (target: <target>)"
)
```

Skip silently if Step 5 produced no Jira key.

### Step 11 — Report

Output:
- **Source**: `<source-branch>`
- **Target**: `<target>`
- **Mode**: `<staging-feature-test | staging-deploy-verify | sub-branch | cross-feature>`
- **Title**: `<pr-title>`
- **Risk**: Low / Medium / High
- **Approval needed**: `<computed: 1 QA/TL | TL sign-off | team norm>`
- **PR URL**: `<url>`
- **CI gates**: Build, Unit tests ≥70%, Lint, SonarQube — all must pass before merge (§15)
- **Next**: depending on mode — e.g. for staging feature test, *"After QA pass, open `/omh-open-pr` to land on master"*; for sub-branch, *"After merge, rebase sibling sub-branches"*.

---

## Error handling

- **Source not pushed yet** — push first with `-u origin <source>`
- **PR already exists for `<source>` → `<target>`** — fetch existing PR, offer to update description instead of creating new
- **MCP Bitbucket/GitHub unavailable** — fall back to `gh` CLI (GitHub) or print body and ask user to create manually
- **Jira ticket closed** — warn: *"Ticket `<KEY>` is Closed/Done. Should this PR still exist?"* — let user confirm
- **Target doesn't exist on remote** — stop: *"`origin/<target>` not found. Create it first or check the spelling."*
- **Source = target** — stop: *"Source and target are the same branch."*

---

## Hard refusals

- Do NOT open PR targeting `develop` (§6 — direct merge, no PR)
- Do NOT open PR targeting `release/*` (§9 — use `/omh-cherry-pick` upstream-first)
- Do NOT open PR targeting `master` — redirect to `/omh-open-pr` (§15 standard flow)
- Do NOT open PR FROM `master` / `develop` / `staging` / `release/*` as source (those are throwaway / release-only)
- Do NOT rebase the source branch onto the **target** — source stays master-based per §3/§6 (rebasing onto `develop`/`staging`/another work branch pollutes the source with un-merged code and breaks "independently deployable")
- Do NOT bypass the rebase check against **master**
- Do NOT auto-rebase or auto-resolve conflicts (per CLAUDE.md "No silent auto-fixes")
- Do NOT fabricate test evidence — flag as pending if missing
- Do NOT use `--force` (use `--force-with-lease` if explicitly asked), `--no-verify`, or `--amend` unless user requests explicitly

---

## What this skill does NOT do

- Does not handle PR to master — that's `/omh-open-pr` (§15 standard flow)
- Does not cherry-pick — that's `/omh-cherry-pick` (§9 upstream-first)
- Does not reset staging — that's `/omh-reset-staging` (§8)
- Does not promote `develop → staging → master` automatically — that's the release flow via `/omh-release`
- Does not rebase source onto target — per §3/§6 source stays master-based; rebase only against `origin/master`
- Does not auto-rebase or auto-resolve conflicts — user resolves manually if mergeability check flags conflicts
- Does not run CI locally — CI runs on the remote after push
- Does not approve or merge — that's reviewer + (where required) Tech Lead

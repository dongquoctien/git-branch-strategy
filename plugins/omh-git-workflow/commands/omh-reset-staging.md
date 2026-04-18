# Reset staging (OMH Git Strategy §7, §15)

**Usage**: `/omh-reset-staging [mode] [extras]`

Examples:
- `/omh-reset-staging` — ask mode via UI
- `/omh-reset-staging feature ELS-123-add-oauth` — pre-release feature testing mode
- `/omh-reset-staging release release/v1.3.0-payment-search` — final verification mode

Parse arguments from: $ARGUMENTS
- Optional mode: `feature` | `release`
- Optional extras: work branch name (for `feature`) or release branch (for `release`)

---

## Rules (from README §7 Staging Flow + §15 Tech Lead Policy + §22)

Staging has **two purposes**, one at a time. Reset switches between them.

| Mode | What goes on staging | When |
|---|---|---|
| **feature** | `origin/master` + one or more `{JIRA-KEY}-*` work branches merged | Before deployment decision — QA verifies feature independently |
| **release** | Exact code from `release/v{X.Y.Z}-*` | Final deployment verification right before tag+deploy |

- **Tech Lead executes** — coordinates with QA on timing (QA must confirm staging not mid-test per §15)
- Force push allowed for Tech Lead only (§22)
- Testing on staging does NOT constitute a deployment decision (§7)
- After reset, developers sync local via `/omh-sync-local`

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended. Bundle independent questions (max 4).

---

## Workflow

### Step 1 — Authorization + QA coordination

Bundle two questions:
```
AskUserQuestion q1:
  question: "Reset staging requires Tech Lead per §15. Who are you?"
  header:   "Role"
  options:
    - "Tech Lead" (Recommended) — description: "Authorized"
    - "Delegate (announced)" — description: "Explicit delegation recorded"
    - "Neither — cancel" — description: "Escalate to Tech Lead"

AskUserQuestion q2:
  question: "QA confirmed staging is not mid-test?"
  header:   "QA check"
  options:
    - "Yes, QA clear to reset" (Recommended) — description: "Proceed"
    - "QA is testing — hold" — description: "Cancel; wait for QA"
    - "Emergency override (hotfix)" — description: "Proceed; document reason"
```

Stop if not authorized or QA mid-test (without emergency).

### Step 2 — Determine mode

If mode not supplied in args, ask:
```
AskUserQuestion:
  question: "Which staging reset mode?"
  header:   "Mode"
  options:
    - "Feature test (master + work branch)" (Recommended) — description: "Pre-release QA verification per §7"
    - "Release verify (release/*)" — description: "Final deploy verification right before tag"
    - "Master only (no merge)" — description: "Rare; baseline reset to clean state"
    - "Cancel" — description: "Abort"
```

### Step 3A — Feature mode flow

Discover work branches:
```bash
git fetch origin --prune
git branch -r | grep -E 'origin/[A-Z]+-[0-9]+' | sed 's|.*origin/||'
```

Ask user to pick via `AskUserQuestion` with multiSelect: true (up to 4 shown; if more, user types via Other):
```
question: "Select work branches to merge into staging (after resetting to master)"
header:   "Branches"
multiSelect: true
options:
  - "<JIRA-KEY-1>-<desc>" — description: "Latest commit by <author>, N commits ahead of master"
  - "<JIRA-KEY-2>-<desc>" — description: "..."
  - "<JIRA-KEY-3>-<desc>" — description: "..."
  - "<JIRA-KEY-4>-<desc>" — description: "..."
```

Preflight per branch: ensure each is rebased onto current master (else merge will conflict):
```bash
git rev-list --count <branch>..origin/master   # must be 0 for a clean merge
```

If any branch is behind, warn user and ask:
```
question: "Branch(es) <names> are behind master. Continue?"
header:   "Behind"
options:
  - "Abort reset" (Recommended) — description: "Have author rebase first"
  - "Proceed (conflicts likely)" — description: "Merge will probably fail; manual resolution needed"
```

Execute:
```bash
git checkout staging
git fetch origin staging
git reset --hard origin/master
# merge each selected branch
git merge --no-ff origin/<branch-1>
git merge --no-ff origin/<branch-2>
# ...
git push --force-with-lease origin staging
```

If any merge fails, abort and stop — do NOT auto-resolve.

### Step 3B — Release mode flow

Discover release branches:
```bash
git branch -r | grep 'origin/release/' | sed 's|.*origin/||'
```

Pick target via `AskUserQuestion` (single select). If none → stop with "No active release branch".

Execute:
```bash
git checkout staging
git fetch origin staging
git reset --hard origin/<release-branch>
git push --force-with-lease origin staging
```

### Step 4 — Confirm execution

Before running Step 3A/3B, show the planned operation and confirm:
```
AskUserQuestion:
  question: "Execute staging reset as described above?"
  header:   "Confirm"
  options:
    - "Cancel" (Recommended) — description: "Review plan first"
    - "Proceed" — description: "IRREVERSIBLE: force push to staging, current staging history overwritten"
```

### Step 5 — Post-reset notification

Print the sync command for developers:
```bash
git fetch origin && git checkout staging && git reset --hard origin/staging
```

Ask whether user has notified QA/team:
```
question: "Notify QA that staging is ready for testing?"
header:   "Notify"
options:
  - "I'll post now" (Recommended) — description: "Print message template with branch list"
  - "Already notified" — description: "Done"
  - "Skip" — description: "Not recommended — QA may miss deploy window"
```

Print a suggested team message template for the user to copy-paste.

### Step 6 — Report

- **Staging mode**: `feature` / `release` / `master`
- **Merged branches** (feature mode): list
- **Reset target** (release mode): `<release-branch>` at `<sha>`
- **Staging HEAD**: `<new-sha>`
- **Next**: QA runs regression; if bugs found in release mode, use `/omh-cherry-pick` (upstream-first)

---

## Hard refusals

- Do NOT reset staging from develop (§7 — never source from develop)
- Do NOT merge a work branch that is behind master without explicit confirmation
- Do NOT skip QA coordination except with explicit emergency override
- Do NOT use raw `--force` — always `--force-with-lease`
- Do NOT auto-resolve merge conflicts in feature mode — abort and report

---

## What this skill does NOT do

- Does not tag or deploy (use `/omh-release --tag` after QA sign-off)
- Does not apply cherry-picks (use `/omh-cherry-pick` — then re-run this skill to re-deploy)
- Does not reset develop (use `/omh-reset-develop`)
- Does not create release branches (use `/omh-release`)

# Cherry-Pick to Release (OMH Git Strategy §9, §15)

**Usage**: `/omh-cherry-pick [commit-sha] [release-branch]`

Examples:
- `/omh-cherry-pick` — auto-discover active release branch, prompt for commit
- `/omh-cherry-pick a3f9c12` — pick specified sha into active release branch
- `/omh-cherry-pick a3f9c12 release/v1.2.0-payment-search` — fully specified

Parse arguments from: $ARGUMENTS
- Optional: commit SHA (short or full)
- Optional: target release branch

---

## Rules (from README §9 Bug Fix During Staging + §10 Hotfix + §15 Tech Lead Policy)

- **Upstream-first**: only cherry-pick commits **already merged to `master`** — never from a work branch or hotfix branch directly
- **Tech Lead must verify the cherry-pick SHA** before it is applied to release branch (§15)
- For hotfix into active release: cherry-pick the merge commit SHA from master — **never merge the hotfix branch** (would pull unrelated commits)
- After cherry-pick: reset staging to release branch so QA re-tests with the fix (§9 step 3)

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended. Tool auto-adds "Other" for free-text. Bundle independent questions (max 4).

---

## Workflow

### Step 1 — Discover active release branches

```bash
git fetch origin --prune
git branch -r | grep 'origin/release/' | sed 's|.*origin/||'
```

If no active release branch → stop with: *"No active release/* branch found. Cherry-pick only applies during an active release cycle."*

If one → use it as default.
If multiple → ask via `AskUserQuestion`:
```
question: "Multiple release branches active. Which target?"
header:   "Target"
options:
  - "<release/vX.Y.Z-a>" — description: "Most recent"
  - "<release/vX.Y.Z-b>" — description: "..."
  - "<release/vX.Y.Z-c>" — description: "..."
```

### Step 2 — Resolve commit SHA

If `$ARGUMENTS` provides a SHA, verify it exists on **master**:
```bash
git fetch origin master
git merge-base --is-ancestor <sha> origin/master  # exit 0 = ancestor
```

If SHA is NOT on master → **refuse**. Print: *"Commit {sha} is not on master. Per §9, cherry-pick only commits already merged to master (upstream-first rule)."*

If no SHA provided, show recent master merges and prompt via `AskUserQuestion`:
```bash
git log origin/master -10 --merges --format='%h %s'
```
```
question: "Pick a commit from master to cherry-pick"
header:   "Commit"
options:
  - "<sha-1> <subject>" (Recommended) — description: "Most recent merge commit"
  - "<sha-2> <subject>" — description: "..."
  - "<sha-3> <subject>" — description: "..."
```
User can pick "Other" to type a specific SHA (still validated as ancestor of master).

### Step 3 — Verify Tech Lead approval

```
question: "Tech Lead must verify this SHA per §15. Confirmed?"
header:   "TL verify"
options:
  - "Yes, Tech Lead approved" (Recommended) — description: "Proceed with cherry-pick"
  - "Tech Lead pending — hold" — description: "Cancel; re-run after approval"
  - "I am the Tech Lead" — description: "Self-approval, proceed"
```

### Step 4 — Preview the cherry-pick

Show what will be applied:
```bash
git show --stat <sha>
```

Print the summary and ask confirmation via `AskUserQuestion`:
```
question: "Apply <sha> '<subject>' to <release-branch>?"
header:   "Confirm"
options:
  - "Apply cherry-pick" (Recommended) — description: "git cherry-pick <sha> on target branch"
  - "Inspect full diff first" — description: "Print full git show <sha> then re-ask"
  - "Cancel" — description: "Abort"
```

### Step 5 — Execute cherry-pick

```bash
git checkout <release-branch>
git pull origin <release-branch>
git cherry-pick <sha>
```

**If cherry-pick fails with conflicts**:
- Do NOT auto-resolve
- Print conflicted files (from `git status`)
- Ask via `AskUserQuestion`:
  ```
  question: "Cherry-pick conflicts in N files. How to proceed?"
  header:   "Conflict"
  options:
    - "Abort cherry-pick" (Recommended) — description: "git cherry-pick --abort; I'll resolve upstream first"
    - "I'll resolve manually" — description: "Stop skill; you resolve files then git cherry-pick --continue"
    - "Skip this commit" — description: "git cherry-pick --skip (rarely correct)"
  ```

**If cherry-pick succeeds**:
```bash
git push origin <release-branch>
```

### Step 6 — Reset staging (§9 step 3)

Cherry-pick without staging reset = QA tests stale code. Ask:
```
question: "Reset staging to <release-branch> so QA re-tests the fix?"
header:   "Reset stg"
options:
  - "Reset + re-deploy staging" (Recommended) — description: "Full flow per §9 step 3"
  - "Skip — staging reset later" — description: "Do manually with /omh-reset-staging"
  - "Cancel" — description: "Don't reset staging"
```

If confirmed:
```bash
git checkout staging
git fetch origin staging
git reset --hard <release-branch>
git push --force-with-lease origin staging
git checkout <release-branch>
```

Remind: announce staging reset in team channel per §15, coordinate with QA.

### Step 7 — Report

- **Cherry-picked**: `<sha>` — `<subject>`
- **Into**: `<release-branch>` at new HEAD `<new-sha>`
- **Staging**: reset / skipped
- **Next**: QA re-tests; if sign-off, `/omh-release --tag`

---

## Hard refusals

- Do NOT cherry-pick from a work branch or hotfix branch directly — commit must be on master first
- Do NOT cherry-pick without Tech Lead verification (§15)
- Do NOT `git merge hotfix/...` into release — use cherry-pick of merge commit SHA (§10 step 5)
- Do NOT apply multiple unrelated commits in one go — cherry-pick one at a time per §10

---

## What this skill does NOT do

- Does not create the upstream fix (use `/omh-new-branch` + `/omh-open-pr` to land fix on master first)
- Does not tag or deploy (use `/omh-release --tag` after QA sign-off)
- Does not handle rebase conflicts on the fix PR itself (that's the author's job before merging to master)

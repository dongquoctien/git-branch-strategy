# Sync Work Branch onto Master (OMH Git Strategy §16)

**Usage**: `/omh-sync-master [strategy]`

Examples:
- `/omh-sync-master` — auto-detect, prefer rebase
- `/omh-sync-master rebase` — force rebase strategy
- `/omh-sync-master merge` — force merge-commit strategy (multi-dev branches)

Parse arguments from: $ARGUMENTS
- Optional: `rebase` (default for single-dev) or `merge` (for multi-dev branches per §16)

---

## Rules (from README §16 Merge Strategy + §15 PR Policy)

- **Default**: rebase for single-developer work branches — keeps history linear per §16
- **Exception**: merge-commit for multi-developer work branches (preserves parallel authorship)
- **Required**: branch must be rebased onto or merged with latest master **before** opening PR — §15 "zero conflicts required"
- Work branch = `{JIRA-KEY}-*` or `hotfix/{JIRA-KEY}-*` — no other branches should run this skill
- Never run on `master`, `develop`, `staging`, `release/*`

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended. Bundle independent questions (max 4).

---

## Workflow

### Step 1 — Preflight checks

Run in parallel:
```bash
git branch --show-current
git fetch origin master
git status --porcelain
git rev-list --count HEAD..origin/master              # commits behind
git rev-list --count origin/master..HEAD              # commits ahead
git log origin/master..HEAD --format='%h %an %s' | head -10
```

Stop conditions:
- Current branch is `master` / `develop` / `staging` / `release/*` → refuse with rule § reference
- Working tree is dirty → prompt via `AskUserQuestion`:
  ```
  question: "Working tree is dirty. Sync requires a clean tree."
  header:   "Dirty"
  options:
    - "Cancel" (Recommended) — description: "Commit or stash manually then re-run"
    - "Stash now" — description: "git stash push -u (restore after sync)"
    - "Discard all" — description: "IRREVERSIBLE: git checkout . && git clean -fd"
  ```
- **0 commits behind master** → print "Already up to date with master." and stop (no-op)
- **0 commits ahead of master** → print "Branch has no commits beyond master; nothing to sync." and stop

### Step 2 — Detect multi-dev branch

Check if branch was worked on by >1 author (heuristic for §16 merge-commit exception):
```bash
git log origin/master..HEAD --format='%ae' | sort -u | wc -l
```

- 1 unique author → **single-dev** → default strategy = `rebase`
- 2+ unique authors → **multi-dev** → default strategy = `merge`

If `$ARGUMENTS` specifies a strategy, use that; otherwise show the inferred default and confirm.

### Step 3 — Confirm strategy

Show current state then ask:

```
<current-branch> is N commits behind master, M commits ahead.
Authors on this branch: <count> (single-dev | multi-dev).
Inferred strategy: <rebase | merge> (per §16).

AskUserQuestion:
  question: "How to sync?"
  header:   "Strategy"
  multiSelect: false
  options:
    - "Rebase (recommended for single-dev)" (Recommended) — description: "git rebase origin/master — linear history"
    - "Merge commit (for multi-dev)" — description: "git merge origin/master — preserves branch structure"
    - "Cancel" — description: "Don't sync"
```

### Step 4 — Dry-run conflict preview

Before actually rebasing/merging, check for likely conflicts:
```bash
# For rebase: list files that differ between branch and master
git diff --name-only HEAD...origin/master

# Optional deeper check: merge-tree (git 2.38+) returns conflict info without touching working tree
git merge-tree --write-tree --merge-base=$(git merge-base HEAD origin/master) HEAD origin/master 2>&1
```

If `merge-tree` reports conflicts, extract conflicting paths and prompt:
```
AskUserQuestion:
  question: "Conflicts likely in N files: <paths>. Continue?"
  header:   "Conflicts"
  multiSelect: false
  options:
    - "Cancel" (Recommended) — description: "Review files manually; pull smaller chunks"
    - "Proceed anyway" — description: "Start rebase/merge; resolve conflicts interactively"
```

If no conflicts predicted → proceed without prompt.

### Step 5 — Execute sync

**Rebase path**:
```bash
git rebase origin/master
```

If conflicts occur:
- Do NOT auto-resolve
- Print `git status` output showing conflicted files
- Print recovery commands:
  ```
  Next steps:
    1. Edit conflicted files to resolve markers (<<<<<<< / >>>>>>>)
    2. git add <resolved-file>
    3. git rebase --continue
  To abort and return to pre-rebase state:
    git rebase --abort
  ```
- Stop skill — user handles manually

**Merge path**:
```bash
git merge --no-ff origin/master -m "Merge master into $(git branch --show-current)"
```

Same conflict handling: never auto-resolve, print recovery commands, stop.

### Step 6 — Post-sync verification

```bash
git rev-list --count HEAD..origin/master     # must be 0 now
git log -5 --oneline --decorate
```

If the post-count is not 0, something went wrong — report and stop.

### Step 7 — Push (with safety)

If the branch was already pushed to remote, rebase rewrote history — need `--force-with-lease`:

```
AskUserQuestion:
  question: "Branch was pushed to origin. Update remote with rewritten history?"
  header:   "Push"
  multiSelect: false
  options:
    - "Push with --force-with-lease" (Recommended) — description: "Safe force — refuses if remote changed"
    - "Skip push (I'll do it manually)" — description: "Local only; push later"
    - "Cancel" — description: "Leave local + remote diverged — not recommended"
```

Execute:
```bash
git push --force-with-lease origin $(git branch --show-current)
```

If push is rejected (remote moved) → stop. Do NOT escalate to `--force`.

### Step 8 — Report

- **Branch**: `<current-branch>`
- **Strategy**: rebase / merge
- **Before sync**: N behind, M ahead of master
- **After sync**: 0 behind master, M (+ new merge commit if merge path)
- **Pushed**: yes / skipped
- **Next**: open PR with `/omh-open-pr`, or continue working

---

## Hard refusals

- Do NOT run on `master` / `develop` / `staging` / `release/*`
- Do NOT use raw `git push --force` — always `--force-with-lease`
- Do NOT auto-resolve conflicts — always stop and defer to user
- Do NOT rebase a branch that has merge commits from work-branch merges without explicit confirmation (merge structure is semantically meaningful)

---

## What this skill does NOT do

- Does not open PR (use `/omh-open-pr`)
- Does not handle develop/staging sync (use `/omh-sync-local`)
- Does not reset throwaway branches (use `/omh-reset-develop` / `/omh-reset-staging`)
- Does not auto-resolve merge conflicts

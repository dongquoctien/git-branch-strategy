# Delete Merged Branch (OMH Git Strategy §12)

**Usage**: `/omh-delete-branch [branch-name]`

Examples:
- `/omh-delete-branch` — detect merged branches, let user pick
- `/omh-delete-branch ELS-123-add-oauth` — delete a specific branch (after verification)

Parse arguments from: $ARGUMENTS
- Optional: branch name to delete (else show merged candidates)

---

## Rules (from README §12 Branch Lifecycle + §11 Naming + §22 Branch Protection)

- **Work branches must be deleted within 3 days of merging to master** (§12)
- **Hotfix branches must be deleted immediately after merging to master** (§12)
- **Release branches must be deleted within 1 day after production deployment** (§12)
- **develop and staging** have NO lifecycle — never delete (§12, §22)
- Verify the branch is actually merged to master (or its merge commit is on master) before delete
- Never force-delete an unmerged branch without explicit confirmation (`-D` instead of `-d`)
- Delete both local AND remote to satisfy §12

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended. Bundle independent questions (max 4).

---

## Workflow

### Step 1 — Discover deletable branches

If `$ARGUMENTS` provides a branch name → validate it and skip to Step 2.

Otherwise auto-discover merged branches. **IMPORTANT**: `git branch --merged` only detects merge-commit merges, NOT squash-merges (which are the default on GitHub). Use `git cherry` for content-based detection:

```bash
git fetch origin --prune

# For each candidate branch, classify:
#   --merged detects merge-commit merges (traditional flow)
#   git cherry detects squash-merges (GitHub default) — outputs "+ sha" only for commits NOT on master
is_merged_into_master() {
  local ref=$1
  # Exit 0 if all commits on branch are already on master (by content, via patch-id)
  ! git cherry origin/master "$ref" 2>/dev/null | grep -q '^+'
}

# Collect candidate work branches (local + remote), then filter
candidates=()
for ref in $(git branch --format='%(refname:short)' | grep -vE '^(master|develop|staging)$'); do
  is_merged_into_master "$ref" && candidates+=("$ref (local)")
done
for ref in $(git branch -r --format='%(refname:short)' | grep -vE 'origin/(master|develop|staging|HEAD)$' | sed 's|origin/||'); do
  is_merged_into_master "origin/$ref" && candidates+=("$ref (remote)")
done
```

Build union of local + remote merged branches (deduped).

If list is empty → report "No merged branches to delete. Checked local + remote against `origin/master` (includes squash-merges)." and stop.

### Step 2 — Verify the target branch

For each candidate branch, gather metadata:
```bash
# Double-check merged status — merge-commit OR squash-merge
if git merge-base --is-ancestor <branch> origin/master; then
  echo "merged (merge-commit)"
elif ! git cherry origin/master <branch> | grep -q '^+'; then
  echo "merged (squash — content on master under different SHA)"
else
  echo "unmerged"
fi

# Does it exist locally / remotely?
git show-ref --verify --quiet refs/heads/<branch>     # local
git ls-remote --heads origin <branch>                 # remote

# Last commit info
git log -1 --format='%h %ar by %an: %s' <branch>
```

Classify branch:
- `hotfix/*` → "should already be deleted per §12" (immediate cleanup)
- `release/*` → "delete within 1 day of deploy per §12"
- `{JIRA-KEY}-*` → "delete within 3 days of merge per §12"
- other patterns → warn that branch doesn't match naming convention

### Step 3 — Pick branch(es) to delete

If multiple candidates, show via `AskUserQuestion` with `multiSelect: true`:

```
AskUserQuestion:
  question: "Select merged branches to delete"
  header:   "Delete"
  multiSelect: true
  options:
    - "<branch-1>" — description: "merged | local+remote | <age>"
    - "<branch-2>" — description: "merged | remote only | <age>"
    - "<branch-3>" — description: "merged | local only | <age>"
    - "<branch-4>" — description: "..."
```

If > 4 candidates, show the 4 oldest + let user type via Other or re-run with explicit name.

If 1 candidate → skip multi-select, go to Step 4.

### Step 4 — Verify delete scope + confirm

For each selected branch, determine what exists (local / remote / both):

```
AskUserQuestion:
  question: "Delete <branch>?"
  header:   "Scope"
  multiSelect: false
  options:
    - "Delete local + remote" (Recommended) — description: "Full cleanup per §12"
    - "Delete local only" — description: "Remote stays (e.g. other devs still use it)"
    - "Delete remote only" — description: "Keep local for reference"
    - "Cancel" — description: "Don't delete"
```

If current branch equals the branch being deleted → refuse, ask user to switch branches first:
```
AskUserQuestion:
  question: "You're currently on <branch>. Switch to master first?"
  header:   "On branch"
  options:
    - "Switch to master then delete" (Recommended) — description: "git checkout master"
    - "Cancel" — description: "Don't delete"
```

### Step 5 — Execute delete

**Local delete** (use `-d`, NOT `-D`, so git refuses if unexpectedly unmerged):
```bash
git branch -d <branch>
```

If `git branch -d` refuses ("not fully merged"), it's likely a **squash-merge** (git native detection doesn't see them). Re-verify via cherry check before forcing:

```bash
if ! git cherry origin/master <branch> | grep -q '^+'; then
  # Content is on master via squash — safe to force-delete local
  git branch -D <branch>
else
  # Genuinely unmerged — prompt user
  ask via AskUserQuestion
fi
```

For the "genuinely unmerged" case:
```
AskUserQuestion:
  question: "Local <branch> has commits not on master. Force delete anyway?"
  header:   "Unmerged"
  options:
    - "Cancel" (Recommended) — description: "Investigate: git log origin/master..<branch>"
    - "Force delete local (-D)" — description: "IRREVERSIBLE: git branch -D discards unmerged commits"
```

**Remote delete**:
```bash
git push origin --delete <branch>
```

If remote delete fails (branch protection, no permission) → surface error, do not retry.

### Step 6 — Post-delete verification

```bash
git branch -a | grep -F <branch>    # should be empty
git remote prune origin             # clean up stale refs
```

### Step 7 — Report

For each deleted branch:
- **Branch**: `<branch>`
- **Local**: deleted / skipped / kept
- **Remote**: deleted / skipped / kept
- **Age**: <age at delete>
- **Next cleanup window**: if still has older merged branches, remind about §12 lifecycle

---

## Hard refusals

- Do NOT delete `master` / `develop` / `staging` (these are permanent or throwaway — never deleted per §22)
- Do NOT delete currently checked-out branch without switching first
- Do NOT use `-D` (force) without explicit confirmation — always try `-d` first
- Do NOT delete a branch that has unmerged commits unless user explicitly forces
- Do NOT delete active `release/*` branches mid-deploy — verify production deploy completed first

---

## What this skill does NOT do

- Does not detect "stale" branches that are unmerged-but-abandoned (§12 reviews those separately)
- Does not delete tags
- Does not reset develop/staging (use `/omh-reset-develop` / `/omh-reset-staging`)
- Does not close PRs (use `gh pr close` or Bitbucket UI)

# Clean Up Worktrees (OMH Git Strategy §12)

**Usage**: `/omh-clean-worktree [worktree-path-or-branch]`

Examples:
- `/omh-clean-worktree` — detect worktrees whose branch is merged to master, let user pick
- `/omh-clean-worktree ELS-123-add-oauth` — clean a specific worktree (after verification)

Parse arguments from: $ARGUMENTS
- Optional: a worktree path or the branch name it holds (else show merged candidates)

This is the cleanup counterpart to `/omh-new-worktree`. Worktrees created for a ticket are throwaway workspaces; like the branch itself they must be removed after merge (§12). By default this skill targets **only worktrees whose branch is already merged to `origin/master`** (including squash-merges), then offers to remove the worktree dir and optionally delete the now-merged branch.

---

## Rules (from README §12 Branch Lifecycle + §22 Branch Protection)

- **Work branches must be deleted within 3 days of merging to master** (§12) — the same window applies to their worktree directories
- Verify the branch is actually merged to master (merge-commit OR squash) before removing (mirrors `/omh-delete-branch`)
- **Never** remove the **main** worktree — only linked worktrees
- Never remove a worktree with **uncommitted or unpushed** changes without explicit confirmation
- `develop` / `staging` / `master` worktrees (if any exist) are off-limits (§22)
- Removing a worktree and deleting its branch are **two separate decisions** — let the user keep the branch if they want

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended. Bundle independent questions (max 4). Destructive options last with `IRREVERSIBLE:` prefix.

---

## Workflow

### Step 1 — Enumerate worktrees

```bash
git fetch origin --prune
git worktree list --porcelain
```

Parse each entry into `{path, branch, head, is_bare, is_main}`. The **first** entry / the one whose path equals `git rev-parse --path-format=absolute --git-common-dir` parent is the **main** worktree — exclude it from all removal candidates.

Also detect **stale administrative entries** (worktree registered but its directory no longer exists on disk) — these are handled by prune in Step 5, regardless of branch status.

If `$ARGUMENTS` names a path or branch → match it against the list and skip to Step 2 for just that one. If no match → report and stop.

### Step 2 — Classify each candidate worktree

For each non-main worktree, determine merge status of its branch against `origin/master` (same logic as `/omh-delete-branch` — `git cherry` catches squash-merges):

```bash
# merged via merge-commit?
git merge-base --is-ancestor <branch> origin/master && echo "merged (merge-commit)"
# else merged via squash? (content on master under a different SHA)
git cherry origin/master <branch> | grep -q '^+' || echo "merged (squash)"
# else
echo "unmerged"
```

And whether the worktree is **clean**:
```bash
git -C <wt_path> status --porcelain          # empty = clean
git -C <wt_path> log --branches --not --remotes -1   # any unpushed commits?
```

Classify each as:
- **merged + clean** → safe to remove (default target)
- **merged + dirty/unpushed** → merged but has local-only changes; warn before removing
- **unmerged** → NOT a default target (excluded unless user explicitly named it in `$ARGUMENTS`)

By default (no `$ARGUMENTS`), the candidate set = worktrees classified **merged** (clean or dirty). If the set is empty:
> "No merged worktrees to clean. Checked all linked worktrees against `origin/master` (includes squash-merges)." — then jump to Step 5 to offer pruning stale entries, and stop.

### Step 3 — Pick worktree(s) to clean

If multiple merged candidates, show via `AskUserQuestion` with `multiSelect: true`:

```
AskUserQuestion:
  question: "Select merged worktrees to remove"
  header:   "Clean"
  multiSelect: true
  options:
    - "<branch-1>" — description: "merged (squash) | clean | <path>"
    - "<branch-2>" — description: "merged | DIRTY: 2 uncommitted | <path>"
    - "<branch-3>" — description: "merged | clean | <path>"
    - "<branch-4>" — description: "..."
```

If > 4 candidates, show the 4 oldest by last-commit date + tell the user they can re-run with an explicit path. If 1 candidate → skip multi-select, go to Step 4.

### Step 4 — Confirm removal scope per selected worktree

For each selected worktree, ask what to do (worktree removal + branch deletion are separate):

```
AskUserQuestion:
  question: "Remove worktree for <branch>?"
  header:   "Scope"
  options:
    - "Remove worktree + delete branch" (Recommended) — description: "Full cleanup per §12: git worktree remove, then delete local+remote branch"
    - "Remove worktree only" — description: "Keep the branch (e.g. you'll re-check it out later)"
    - "Cancel" — description: "Leave this worktree as-is"
```

**If the worktree is dirty/unpushed**, do NOT offer a default-safe removal — require an explicit confirmation first:
```
AskUserQuestion:
  question: "Worktree <path> has uncommitted/unpushed changes. Remove anyway?"
  header:   "Dirty WT"
  options:
    - "Cancel" (Recommended) — description: "Inspect: cd <path> && git status. Commit/push first."
    - "Force remove worktree" — description: "IRREVERSIBLE: git worktree remove --force discards uncommitted changes"
```

If the user is **currently inside** the worktree being removed → refuse and tell them to `cd` to the main repo first (you cannot remove the worktree you're standing in).

### Step 5 — Execute

**Remove worktree** (plain remove refuses if dirty — that's the safety we want):
```bash
git worktree remove "<wt_path>"
```
Only if the user explicitly chose "Force remove" in Step 4:
```bash
git worktree remove --force "<wt_path>"
```

**Delete branch** (only if user chose "+ delete branch") — reuse `/omh-delete-branch` semantics: try `-d`, fall back to `-D` only if cherry-check confirms a squash-merge:
```bash
git branch -d <branch> || {
  git cherry origin/master <branch> | grep -q '^+' \
    || git branch -D <branch>     # safe: content on master via squash
}
git push origin --delete <branch>   # remote (skip if user kept branch / remote already gone)
```
> Prefer delegating the branch deletion to `/omh-delete-branch` if it's available, to keep one source of truth for delete safety. Otherwise inline the logic above.

**Prune stale entries** (always, at the end):
```bash
git worktree prune
git remote prune origin
```

If any step fails (branch protection, permission, locked worktree) → surface the error verbatim, do not retry or force.

### Step 6 — Report

For each processed worktree:
- **Branch**: `<branch>`
- **Worktree**: removed / kept / force-removed
- **Branch local**: deleted / kept
- **Branch remote**: deleted / kept / already gone
- **Merge status at removal**: merged (merge-commit) / merged (squash)
- **Stale entries pruned**: <count>
- **Reminder**: if older merged worktrees remain, note the §12 3-day cleanup window

---

## Hard refusals

- Do NOT remove the **main** worktree
- Do NOT remove a worktree for `master` / `develop` / `staging` (§22)
- Do NOT remove the worktree you are currently `cd`'d into — switch to main repo first
- Do NOT use `--force` on `git worktree remove` without explicit confirmation
- Do NOT force-delete an **unmerged** branch — `git branch -D` only after a cherry-check confirms a squash-merge, otherwise ask
- Do NOT remove an unmerged worktree by default — it must be named explicitly in `$ARGUMENTS` and still pass the dirty-tree confirmation

---

## What this skill does NOT do

- Does not create worktrees (use `/omh-new-worktree`)
- Does not detect "stale-but-unmerged" abandoned worktrees as default targets (§12 reviews those separately) — only merged ones, unless explicitly named
- Does not reset develop/staging (use `/omh-reset-develop` / `/omh-reset-staging`)
- Does not close PRs (use `gh pr close` or the Bitbucket UI)

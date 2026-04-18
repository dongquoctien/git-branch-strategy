# Sync local develop / staging (OMH Git Strategy §6, §7)

**Usage**: `/omh-sync-local [branch]`

Examples:
- `/omh-sync-local` — auto-detect which local branch needs sync
- `/omh-sync-local develop`
- `/omh-sync-local staging`

Parse arguments from: $ARGUMENTS
- Optional: `develop` or `staging` (else auto-detect)

---

## Rules (from README §6, §7)

- `develop` and `staging` are **throwaway** — Tech Lead can reset remote at any time
- After a reset, local develop/staging will diverge from remote — you must **hard reset** local to match remote, otherwise local history conflicts with force-pushed remote
- Sync command:
  - develop: `git checkout develop && git fetch origin && git reset --hard origin/develop`
  - staging: `git fetch origin && git checkout staging && git reset --hard origin/staging`
- Never create branches from develop/staging
- Never work directly on develop/staging — sync is only for pulling in the reset remote state

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended. Bundle independent questions (max 4).

---

## Workflow

### Step 1 — Detect divergence

Run in parallel:
```bash
git fetch origin --prune
git rev-list --left-right --count develop...origin/develop    # local vs remote
git rev-list --left-right --count staging...origin/staging
git status --porcelain
git branch --show-current
```

For each of `develop` and `staging`, compare local vs remote:
- If local has commits remote doesn't AND vice versa → **diverged** (reset needed)
- If local is behind only → fast-forward is enough
- If local == remote → no-op

Build candidate list of branches needing sync.

### Step 2 — Working tree check

If working tree is dirty (including on a feature branch that doesn't need sync), abort and prompt:
```
AskUserQuestion:
  question: "Working tree is dirty. Sync require checking out develop/staging — safe to proceed?"
  header:   "Dirty"
  options:
    - "Cancel" (Recommended) — description: "Commit or stash first (run /omh-commit)"
    - "Stash and proceed" — description: "git stash push -u; you pop after sync"
    - "Discard local changes" — description: "IRREVERSIBLE: git checkout . && git clean -fd"
```

### Step 3 — Pick branches to sync

If no branch needs sync → report "all branches in sync" and stop.

If one branch → use it.

If both need sync → ask via `AskUserQuestion`:
```
question: "Which branches to sync?"
header:   "Branches"
multiSelect: true
options:
  - "develop (diverged: +N local / -M remote)" — description: "Hard reset to origin/develop"
  - "staging (diverged: +N local / -M remote)" — description: "Hard reset to origin/staging"
```

### Step 4 — Confirm destructive reset

For each selected branch, show the commits that will be **discarded** (local commits not on remote):
```bash
git log origin/develop..develop --oneline
```

If non-empty list → ask user:
```
question: "Local <branch> has N commits not on remote. These will be LOST on reset."
header:   "Confirm"
options:
  - "Cancel this branch" (Recommended) — description: "Review commits first; maybe cherry-pick to a work branch"
  - "Reset anyway" — description: "IRREVERSIBLE: local commits discarded"
```

If empty (local is just behind) → proceed without extra confirmation.

### Step 5 — Execute sync

For each confirmed branch:
```bash
git checkout <branch>
git fetch origin <branch>
git reset --hard origin/<branch>
```

Return to original branch after all syncs:
```bash
git checkout <original-branch-from-step-1>
```

If you stashed in Step 2, remind user to `git stash pop` (do not auto-pop — user should verify which changes to restore).

### Step 6 — Report

For each synced branch:
- **develop**: synced to `origin/develop @ <sha>` (N commits discarded)
- **staging**: synced to `origin/staging @ <sha>` (N commits discarded)
- **Original branch**: restored to `<branch>`
- **Stash**: popped / kept / none

If local commits were discarded, remind user:
> "If the discarded commits were valuable work, they should be on a `{JIRA-KEY}-*` work branch (§6 rule). Check reflog: `git reflog show <branch>` to recover commits if needed."

---

## Hard refusals

- Do NOT sync while working tree is dirty (unless user explicitly stashes or discards)
- Do NOT use raw `reset --hard` without showing commits that will be lost
- Do NOT auto-pop stash — user should verify before restoring

---

## What this skill does NOT do

- Does not execute the remote reset (only Tech Lead does that via `/omh-reset-develop` / `/omh-reset-staging`)
- Does not merge work branches into develop (developers do that manually per §6)
- Does not re-run CI locally (CI runs on remote after reset)

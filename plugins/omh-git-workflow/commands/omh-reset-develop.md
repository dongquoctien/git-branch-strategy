# Reset develop to master (OMH Git Strategy §6, §15)

**Usage**: `/omh-reset-develop`

No arguments required.

---

## Rules (from README §6 Development Flow + §15 Tech Lead Policy + §22 Branch Protection)

- **develop is throwaway** — reset freely, no history preservation needed
- **Tech Lead executes** — must announce in team channel before reset (§15)
- Reset baseline = `origin/master` (never from staging/release)
- After reset, develop == master, then in-progress work branches are re-merged as needed
- Force push allowed (Tech Lead only per §22)
- Purpose: eliminates need for back-merge after hotfixes — develop naturally picks up hotfix on next reset
- Developers must sync local develop after reset (use `/omh-sync-local`)

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended. Bundle independent questions (max 4).

---

## Workflow

### Step 1 — Authorization check

```
AskUserQuestion:
  question: "Reset develop requires Tech Lead per §15. Who are you?"
  header:   "Role"
  options:
    - "Tech Lead" (Recommended) — description: "Authorized; proceed"
    - "Delegate (announced in team)" — description: "Explicit delegation recorded in team channel"
    - "Neither — cancel" — description: "Escalate to Tech Lead"
```

If not authorized → stop.

### Step 2 — Announcement check

Per §15, reset must be announced before execution to avoid clobbering mid-integration work.

```
AskUserQuestion:
  question: "Has the reset been announced in team channel?"
  header:   "Announced"
  options:
    - "Yes, announced" (Recommended) — description: "Proceed"
    - "Not yet" — description: "Cancel; announce first, then re-run"
    - "Skip announcement (emergency)" — description: "Proceed; log reason in post-action note"
```

### Step 3 — Preflight state inspection

Run in parallel:
```bash
git fetch origin --prune
git log origin/develop..origin/master --oneline | wc -l    # commits develop will gain
git log origin/master..origin/develop --oneline            # commits develop will LOSE (in-progress merges)
git status --porcelain
```

Show a diff summary to user, especially commits that will be **discarded** from develop (these are usually merged-in work branches that need to be re-merged after reset — per §6).

If working tree is dirty, stop and redirect to `/omh-commit` or stash.

### Step 4 — Confirm destructive action

Show summary, then ask:
```
AskUserQuestion:
  question: "Reset develop to origin/master? N commits will be dropped from develop (in-progress integration merges)."
  header:   "Reset dev"
  options:
    - "Cancel" (Recommended) — description: "Review dropped commits first"
    - "Reset develop now" — description: "IRREVERSIBLE: force push, existing develop history is overwritten"
    - "Show dropped commits in detail" — description: "Print full git log then re-ask"
```

### Step 5 — Execute reset

```bash
git checkout develop
git fetch origin
git reset --hard origin/master
git push --force-with-lease origin develop
```

**Important**: use `--force-with-lease` (safer than `--force`). If push is rejected because remote moved, stop and ask user to re-check — do NOT escalate to raw `--force`.

### Step 6 — Post-reset notification

Print the sync command developers need to run locally:
```bash
git checkout develop && git fetch origin && git reset --hard origin/develop
```

Ask via `AskUserQuestion` whether to broadcast this in team channel (skill itself does not post — just prompts user):
```
question: "Reset complete. Notify team with the sync command?"
header:   "Notify"
options:
  - "Yes, I'll post now" (Recommended) — description: "Copy sync command to clipboard instructions below"
  - "Already posted pre-reset" — description: "Done earlier; skip"
  - "Skip notification" — description: "Not recommended"
```

### Step 7 — Report

- **develop reset**: `origin/develop = origin/master @ <sha>`
- **Commits dropped**: N (list in §3 preflight)
- **Sync command for devs**:
  ```bash
  git checkout develop && git fetch origin && git reset --hard origin/develop
  ```
- **Next**: developers re-merge any in-progress work branches into develop for integration testing (no PR required per §6)

---

## Hard refusals

- Do NOT reset develop from staging or release/* — only from origin/master (§6)
- Do NOT use raw `--force` — always `--force-with-lease`
- Do NOT skip announcement unless user explicitly marks as emergency
- Do NOT reset while working tree is dirty

---

## What this skill does NOT do

- Does not notify team channel (prints the message for user to post)
- Does not sync developer local machines (they run `/omh-sync-local` themselves)
- Does not reset staging (use `/omh-reset-staging`)
- Does not re-merge in-progress work branches (devs do that per §6)

# Squash Branch Commits (OMH Git Strategy §16)

**Usage**: `/omh-squash [message]`

Examples:
- `/omh-squash` — auto-suggest message from branch name + commits
- `/omh-squash "feat(auth): add Google OAuth login [ELS-234]"` — use exact message

Parse arguments from: $ARGUMENTS
- Optional: free-text squash message used verbatim if provided (still validated against §14)

---

## Rules (from README §14 Commit Convention + §16 Merge Strategy)

- §16: `{JIRA-KEY}-desc → master` uses **rebase before PR** for single-developer branches → squash to a single commit gives the cleanest linear history
- §14: the resulting commit must follow `<type>(<scope>): <subject>` (≤50 chars) + 72-char body wrap + Jira key in trailer (`Refs: KEY-N`)
- Squash range = `merge-base(HEAD, origin/master)..HEAD` — never reach commits already on master
- Work branch only: `{JIRA-KEY}-*`, `hotfix/{JIRA-KEY}-*`, or local chore branches off master
- Refuse on `master`, `develop`, `staging`, `release/*`
- Multi-author commits in the range → preserve attribution via `Co-Authored-By:` trailers (never silently drop authorship)

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended/safest. Destructive options last with `IRREVERSIBLE:` prefix in description. Bundle independent questions in one call (max 4). Never print "type 1/2/3" prompts.

---

## Workflow

### Step 1 — Preflight checks

Run in parallel:
```bash
git branch --show-current
git fetch origin master
git status --porcelain
git rev-parse --verify origin/master
```

Stop conditions (refuse with §16 reference):
- Current branch is `master` / `develop` / `staging` / `release/*` → refuse
- Working tree is dirty → ask via `AskUserQuestion`:
  ```
  question: "Working tree is dirty. Squash requires a clean tree."
  header:   "Dirty"
  options:
    - "Cancel" (Recommended) — description: "Commit or stash manually then re-run"
    - "Stash now" — description: "git stash push -u (restore after squash with git stash pop)"
    - "Discard all" — description: "IRREVERSIBLE: git checkout . && git clean -fd"
  ```
  If "Discard all" → follow-up confirmation `AskUserQuestion`:
  ```
  question: "Really discard all local changes? This cannot be undone."
  header:   "Confirm"
  options:
    - "Cancel" (Recommended) — description: "Keep changes"
    - "Yes, discard" — description: "IRREVERSIBLE"
  ```

### Step 2 — Detect range

```bash
merge_base=$(git merge-base HEAD origin/master)
n_commits=$(git rev-list --count ${merge_base}..HEAD)
git log ${merge_base}..HEAD --format='%h %an <%ae> %s'
```

Stop conditions:
- `n_commits == 0` → "Branch has no commits beyond master; nothing to squash." Stop.
- `n_commits == 1` → "Branch already has a single commit beyond master; squash is a no-op. Use `/omh-commit --amend` if you want to edit the message." Stop.

Show the user a one-screen summary:
> Branch `<current>` has **N commits** since merge-base `<short-sha>` with `origin/master`.
> ```
> abc1234 Alice <a@x> feat(auth): add OAuth scaffolding
> def5678 Bob   <b@x> feat(auth): wire token exchange
> 9012345 Alice <a@x> test(auth): cover token refresh edge cases
> ```

### Step 3 — Detect merge commits in range (hard refusal trigger)

```bash
git log ${merge_base}..HEAD --merges --format='%h %s'
```

If output is non-empty, the range contains merge commits — squashing would discard semantically meaningful merge structure. **Refuse** with:

> The range contains merge commits — squashing would discard branch-merge structure.
> Run `/omh-sync-master rebase` first to linearize, then re-run `/omh-squash`.
> Aborting (per §16 — merge structure is meaningful for multi-dev branches).

Stop. Do NOT prompt to override.

### Step 4 — Detect multi-author and prepare Co-Authored-By trailers

```bash
git log ${merge_base}..HEAD --format='%an <%ae>' | sort -u
```

If >1 unique author:
- Identify the **current user** (`git config user.name` + `user.email`) — this is the author of the squash commit
- All **other** authors become `Co-Authored-By:` trailers (one per line, sorted, deduplicated)
- Show the user a one-line note (no prompt — auto-applied per §16 spirit of preserving attribution):
  > Multi-author range detected: 2 co-authors. Adding `Co-Authored-By:` trailers automatically.

Save the trailers — they will be appended to the final commit message body in Step 6.

### Step 5 — Build squash message candidates

Extract Jira key from current branch name (regex: `^(?:hotfix/)?([A-Z]+-[0-9]+)-`):
- If matched → `jira_key`, used in `Refs: <jira_key>` trailer (per §14)
- If no Jira key in branch name (e.g. `chore/...` branches) → no `Refs:` trailer; warn the user but allow

If `$ARGUMENTS` provides a verbatim message, **skip** this step and go to Step 6 with that message (still validated).

Otherwise build 3 candidates from the commit log + branch name:

- **Candidate A — First commit's subject**: keep the subject of the chronologically first commit; body = bullet list of all commit subjects
- **Candidate B — Branch-derived subject**: derive from the kebab-case description after the Jira key (`ELS-234-add-google-oauth-login` → `feat(auth): add Google OAuth login`); type/scope inferred from first commit; body = bullet list
- **Candidate C — Last commit's subject**: the most recent subject (often the most polished); body = bullet list

Each candidate body is structured as:
```
<subject>

- <commit 1 subject>
- <commit 2 subject>
- <commit 3 subject>

Refs: <jira_key>           ← only if jira_key was detected
Co-Authored-By: ...        ← only if Step 4 found co-authors
```

Ask via `AskUserQuestion`:
```
question: "Choose squash commit message"
header:   "Message"
options:
  - "<Candidate A subject>" (Recommended) — description: "first-commit subject + bullet body"
  - "<Candidate B subject>" — description: "branch-name-derived subject + bullet body"
  - "<Candidate C subject>" — description: "last-commit subject + bullet body"
  # User can select "Other" to type a custom subject (tool adds this automatically)
```

If user picks "Other", they provide a custom subject — body is still auto-built (bullets + trailers).

### Step 6 — Validate the chosen message against §14

Hard checks (reject and re-prompt with the same `AskUserQuestion`, prepending the error to the question text):

| Check | Rule |
|---|---|
| Subject matches `^(feat\|fix\|refactor\|infra\|hotfix\|docs\|test\|other)\([a-z][a-z0-9-]*\): [a-z]` | §14 valid types + lowercase scope + lowercase subject |
| Subject ≤ 50 chars (full line) | §14 |
| Subject not in `["fix bug", "update code", "wip", "changes", "misc", "stuff"]` | §14 vague-subject reject list |
| Subject has no trailing `.` | §14 |
| Body lines ≤ 72 chars | §14 |
| Blank line between subject and body | §14 |
| Branch is `hotfix/*` → type must be `fix`, NOT `hotfix` | §14 note |
| If `jira_key` was detected → message contains `Refs: <jira_key>` trailer | §14 |

If any check fails, surface the specific violation; do NOT auto-fix.

### Step 7 — Execute squash

Use `git reset --soft` from the merge-base, then commit. This is byte-for-byte equivalent to `git rebase -i origin/master` with all picks marked `squash`, but portable across PowerShell/Bash without `GIT_SEQUENCE_EDITOR` / `GIT_EDITOR` hacks.

Pass the message directly via `git commit -m` using a HEREDOC — avoids the temp-file path issues when `.git/` is sandboxed or when `git rev-parse --git-dir` returns a relative path:

```bash
# Reset HEAD to merge-base; index + working tree keep all squashed changes staged
git reset --soft "$merge_base"

# Commit with the prepared multi-line message via HEREDOC
git commit -m "$(cat <<'EOF'
<final_message_subject>

<final_message_body>

Refs: <jira_key>
Co-Authored-By: <name> <email>
EOF
)"
```

(Avoid `git commit -F .git/SQUASH_MSG` — `--git-dir` may resolve to a relative path that breaks across cwd changes, and some sandboxes refuse writes inside `.git/`.)

Do NOT pass `--no-verify`. If pre-commit hooks fail, stop and surface the error — user fixes the underlying issue and re-runs.

### Step 8 — Post-squash verification

```bash
git rev-list --count origin/master..HEAD     # must be exactly 1
git log -1 --stat
```

If the count is not 1, something went wrong — report:
> Squash verification failed: expected 1 commit ahead of master, got <N>. Branch state may be inconsistent. Run `git reflog` to recover.

Do NOT attempt auto-recovery.

### Step 9 — Push prompt (default Cancel)

The branch history was rewritten — pushing requires `--force-with-lease`. Default is **not to push** so the user can verify with `git log` first.

**Detect whether the branch has its own remote-tracking ref** — NOT just any upstream. A common trap: `git checkout -b chore/foo origin/master` sets upstream to `origin/master`, so a naive `git rev-parse @{u}` returns truthy and would suggest pushing onto master.

Use a **specific** remote-branch check:

```bash
current_branch=$(git branch --show-current)
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
remote_branch_exists=$(git ls-remote --heads origin "$current_branch" | wc -l)
```

**Hard refusal** — if `upstream` is in `["origin/master", "origin/develop", "origin/staging"]` or matches `origin/release/*`, NEVER prompt to push:
> Refusing to push: branch `<current>` is tracking `<upstream>`, which is a protected branch.
> Run `git branch --unset-upstream` and re-push with `git push -u origin <current>` to set the correct upstream first.
> Stop.

Otherwise:
- `remote_branch_exists == 0` → branch has never been pushed under its own name. Print:
  > Branch not pushed yet. Push later with `git push -u origin <current>` (no `--force` needed for the first push).
  
  Skip the prompt.
- `remote_branch_exists == 1` AND upstream points to `origin/<current_branch>` → safe to ask:
  ```
  question: "Squash done. Push to origin/<current_branch>? History was rewritten — needs --force-with-lease."
  header:   "Push"
  options:
    - "Cancel" (Recommended) — description: "Verify with `git log` first; push manually when ready"
    - "Push with --force-with-lease" — description: "Safe force — refuses if remote moved since last fetch"
  ```

If user picks "Push with --force-with-lease":
```bash
git push --force-with-lease origin "$current_branch"
```

If push is rejected (remote diverged) → stop. Do NOT escalate to raw `--force`. Report:
> Push rejected — remote moved since last fetch. Re-run `git fetch origin` and resolve before retrying.

### Step 10 — Report

- **Branch**: `<current-branch>`
- **Squashed**: N commits → 1 commit
- **Base**: `origin/master @ <short-sha>`
- **New SHA**: `<new-commit-short-sha>`
- **Subject**: `<final subject>`
- **Co-authors preserved**: yes (M trailers) / no
- **Pushed**: yes / skipped (default)
- **Stash**: `git stash pop` to restore (only if Step 1 stashed)
- **Next**: `/omh-sync-master` (if behind master), then `/omh-open-pr`

---

## Hard refusals

- Do NOT run on `master` / `develop` / `staging` / `release/*`
- Do NOT push to `origin/master`, `origin/develop`, `origin/staging`, `origin/release/*` — refuse even if the current branch's upstream points there (common after `git checkout -b X origin/master`)
- Do NOT squash a range containing merge commits — refer to `/omh-sync-master rebase`
- Do NOT use raw `git push --force` — only `--force-with-lease`
- Do NOT pass `--no-verify` to bypass pre-commit hooks
- Do NOT silently drop co-author attribution — always add `Co-Authored-By:` trailers when the range is multi-author
- Do NOT auto-recover from a failed verification (Step 8) — surface `git reflog` to the user
- Do NOT write to `.git/` for scratch files — use `git commit -m` with HEREDOC instead (sandbox + relative-path safe)

---

## What this skill does NOT do

- Does not sync with master (use `/omh-sync-master` if branch is behind master before squashing)
- Does not open PR (use `/omh-open-pr` after squashing)
- Does not delete the branch (use `/omh-delete-branch`)
- Does not amend an existing commit (use `git commit --amend` directly — single-commit case is a no-op for this skill)
- Does not squash across `master` (range is hard-bounded by `merge-base(HEAD, origin/master)`)

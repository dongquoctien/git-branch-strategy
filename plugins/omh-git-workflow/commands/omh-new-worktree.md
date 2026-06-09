# Create Work Branch in a Worktree (OMH Git Strategy §6, §11, §12)

**Usage**: `/omh-new-worktree <JIRA-KEY> [description] [repo-hint]`

Example: `/omh-new-worktree ELS-123 add-google-oauth-login`

Parse arguments from: $ARGUMENTS
- First token that matches `^[A-Z]+-[0-9]+$` (or is a Jira URL containing one) → **jira_key**
- Tokens that look like kebab-case → **description**
- Tokens that look like a repo name or GitHub/Bitbucket URL → **repo_hint**

This is the worktree variant of `/omh-new-branch`. It creates the **same** `{JIRA-KEY}-{description}` branch from `origin/master`, but checks it out into a **separate git worktree directory** instead of switching the current working tree. This lets you work on the ticket in parallel without disturbing whatever is checked out in the main repo.

---

## Rules (from README §11 Branch Creation Policy + §12 Lifecycle)

- Work branches use the **bare Jira key as prefix** — NO `feature/` or `bugfix/` prefix (§11)
- Pattern: `{JIRA-KEY}-{description}` (e.g. `ELS-123-add-login-with-google`) (§11)
- Description: lowercase kebab-case, specific (not `fix-bug`, not `update-code`) (§11)
- **Always branched from latest `origin/master`** — never from develop/staging/HEAD (§6/§11)
- Jira ticket must exist and be linked (§11)
- The worktree directory is a throwaway workspace — like the branch, it must be cleaned up after merge (use `/omh-clean-worktree`, see §12)
- **Worktree location** is fixed at `<main-repo>/.claude/worktree/{branch-name}` so worktrees stay grouped and out of sibling repo dirs
- The skill must ensure `.claude/worktree/` is gitignored before creating a worktree there — never let worktree contents become committable in the main repo

---

## Interaction convention — ALWAYS use AskUserQuestion

**Do NOT print numbered options as text and wait for the user to type a number.** Every time this skill needs user input, call the `AskUserQuestion` tool so the user can select with arrow keys / click.

Rules when calling `AskUserQuestion`:
- `header`: ≤12 chars, chip-style label (e.g. `"Description"`, `"WT exists"`)
- `options`: 2–4 items, mutually exclusive unless `multiSelect: true`
- Do NOT add an "Other" option — the tool adds it automatically for free-text input
- First option is the recommended/safest choice — suffix label with `" (Recommended)"` when appropriate
- Destructive options go last, with description starting with `"IRREVERSIBLE: "`
- Always provide a Cancel option when the action is non-trivial
- Multiple independent questions in the same step → pass them together in ONE `AskUserQuestion` call (max 4 questions)

---

## Workflow

### Step 1 — Parse & validate arguments

Extract:
- `jira_key` from first `^[A-Z]+-[0-9]+$` token or Jira URL (regex against `browse/([A-Z]+-[0-9]+)`)
- `description` from kebab-case tokens (if any)
- `repo_hint` from GitHub/Bitbucket URLs or repo names

Validations (reject immediately, do NOT prompt to fix):
- `jira_key` matches `^[A-Z]+-[0-9]+$` — if missing, stop with: *"Jira key missing or invalid. Expected ELS-123, OMH-4857, or a Jira URL."*
- If `description` is provided: must match `^[a-z0-9][a-z0-9-]*[a-z0-9]$` and not be in `["fix-bug", "update-code", "wip", "temp", "test"]`
- Full branch name length ≤ 80 chars

Confirm we are inside a git repo. If the current directory is **itself a linked worktree** (not the main worktree), resolve the **main worktree** path — worktrees must be created relative to the main repo, not nested inside another worktree:

```bash
git rev-parse --is-inside-work-tree            # must be true
git_common=$(git rev-parse --git-common-dir)   # points into the MAIN repo's .git
main_repo=$(git rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')
```

Use `main_repo` as the base for the worktree path in Step 4. If `description` is missing, continue to Step 2 (need the Jira summary to suggest candidates).

### Step 2 — Verify Jira ticket exists

Call `mcp__mcp-atlassian__jira_get_issue(issue_key=jira_key)`.

- If not found → stop with *"Jira ticket {jira_key} not found"*
- Extract: `summary`, `issue_type`, `status`, `assignee`

Show a brief one-line confirmation (no prompt yet):
> **ELS-1000** — "[demo] Test skill git branch strategy" · Task · To Do · Tom

If status is `Done` or `Closed`, add a question to the Step 3 bundle:

```
AskUserQuestion question:
  question: "Ticket is already {status}. Proceed?"
  header:   "Closed tkt"
  options:
    - label: "Cancel" (Recommended) — description: "Don't create worktree; pick a different ticket"
    - label: "Proceed anyway" — description: "Reopen work on a closed ticket"
```

### Step 3 — Gather missing inputs in a single AskUserQuestion call

Build the list of questions (up to 4); include only those actually needed.

**Q1 — Description** (only if missing):
Generate 3 kebab-case candidates from the Jira summary:
- Candidate A: shortest meaningful phrase (2–3 words)
- Candidate B: tool/feature-specific keywords
- Candidate C: outcome/action-focused

```
question: "Choose a branch description"
header:   "Description"
options:
  - label: "<candidate-A>" — description: "short, general"
  - label: "<candidate-B>" — description: "specific focus"
  - label: "<candidate-C>" — description: "outcome-focused"
```

Validate the choice (or custom input) against the kebab-case regex; if invalid, re-prompt with an error note prepended.

**Q2 — Repo target** (only if `repo_hint` is provided and differs from the current main repo):

Probe filesystem (`../{name}`, `D:/Github/{name}`, sibling dirs). The worktree is always created under the **target** repo's `.claude/worktree/`.

```
question: "Target repo doesn't match current directory. What to do?"
header:   "Repo target"
options:
  - label: "Stay here" (Recommended) — description: "Create worktree under current repo: {main_repo}"
  - label: "Switch to {found-path}" — description: "Use existing local clone as the base repo"
  - label: "Cancel" — description: "I'll navigate manually"
```

> Note: unlike `/omh-new-branch`, a **dirty working tree does NOT block** this skill — a worktree is created in a fresh directory and leaves the current tree untouched. Do not prompt about uncommitted changes.

**Call `AskUserQuestion` once** with the applicable questions bundled.

### Step 4 — Pre-flight: gitignore + branch/worktree collisions

Compute:
- `branch = {JIRA-KEY}-{description}`
- `wt_dir = {main_repo}/.claude/worktree/{branch}`

**4a. Ensure `.claude/worktree/` is gitignored** in the main repo (per Rules). Check the repo's `.gitignore`:
- If a line matching `.claude/worktree/` (or a broader ignore that covers it) is absent, append `\n# git worktrees created by /omh-new-worktree\n.claude/worktree/\n` to `{main_repo}/.gitignore`.
- This is the **one** auto-edit this skill performs without asking, because committing worktree contents into the main repo would be a footgun. Mention it in the final report.

**4b. Branch collision** — if `branch` already exists (local or remote):
```bash
git show-ref --verify --quiet refs/heads/{branch}      # local exists?
git ls-remote --heads origin {branch}                  # remote exists?
```
- If it exists, do NOT silently reuse or force. Ask:
```
AskUserQuestion:
  question: "Branch {branch} already exists. How to proceed?"
  header:   "Branch ex"
  options:
    - label: "Cancel" (Recommended) — description: "Pick a different description, or use /omh-clean-worktree if it's a stale worktree"
    - label: "Check out existing branch in a worktree" — description: "Create worktree FROM the existing branch (no new branch, no reset)"
```
If the user keeps the existing branch, in Step 5 use `git worktree add {wt_dir} {branch}` (no `-b`).

**4c. Worktree-path collision** — if `wt_dir` already exists on disk or is a registered worktree:
```bash
git worktree list --porcelain | grep -F "{wt_dir}"
```
- If registered/non-empty → stop and point the user to `/omh-clean-worktree`. Do NOT delete it here.

### Step 5 — Execute

Always fetch first; never branch from stale master:

```bash
git fetch origin master
```

New branch + worktree in one step (default path):
```bash
git worktree add -b {branch} "{wt_dir}" origin/master
```

Existing-branch path (from 4b):
```bash
git worktree add "{wt_dir}" {branch}
```

Rules:
- Never create from current HEAD — always from `origin/master` for new branches
- Never create from `develop` or `staging`
- If `git worktree add` fails → stop, report verbatim, do NOT force or delete anything

### Step 6 — Report

Print:
- **Jira**: `{jira_key}` — `{summary}`
- **Branch**: `{branch}`
- **Based on**: `origin/master @ <short-sha>` (or "existing branch" if 4b path)
- **Worktree**: `{wt_dir}`
- **gitignore**: "added `.claude/worktree/` to .gitignore" (only if 4a edited it)
- **Enter it**: `cd "{wt_dir}"`
- **Next**: `cd` into the worktree → implement → `/omh-commit` → `/omh-open-pr`
- **Cleanup later**: `/omh-clean-worktree` after the PR merges (§12)

---

## Error handling

- **Not a git repo**: stop with clear message
- **Fetch fails (no network)**: stop — do not create a worktree from stale master
- **Branch already exists**: ask (Step 4b) — do not force or reset
- **Worktree path already registered/non-empty**: stop, point to `/omh-clean-worktree`
- **Jira MCP unavailable**: `AskUserQuestion` with `["Cancel", "Proceed without Jira verification"]` — default Cancel

---

## Hard refusals

- Do NOT create a worktree branch from `develop`, `staging`, or current HEAD — only `origin/master` (or an explicitly-chosen existing branch in 4b)
- Do NOT use `--force` on `git worktree add` to clobber an existing path
- Do NOT delete or overwrite an existing worktree directory — that's `/omh-clean-worktree`'s job
- Do NOT `git stash` / discard the current working tree — a worktree never needs to touch it

---

## What this skill does NOT do

- Does not switch the current working tree's branch (use `/omh-new-branch` for an in-place checkout)
- Does not remove worktrees (use `/omh-clean-worktree`)
- Does not create PRs (use `/omh-open-pr`)
- Does not create hotfix branches (use `/omh-hotfix` — different rules per §10)

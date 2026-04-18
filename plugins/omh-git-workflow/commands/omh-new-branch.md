# Create Work Branch (OMH Git Strategy §6, §11)

**Usage**: `/omh-new-branch <JIRA-KEY> [description] [repo-hint]`

Example: `/omh-new-branch ELS-123 add-google-oauth-login`

Parse arguments from: $ARGUMENTS
- First token that matches `^[A-Z]+-[0-9]+$` (or is a Jira URL containing one) → **jira_key**
- Tokens that look like kebab-case → **description**
- Tokens that look like a repo name or GitHub/Bitbucket URL → **repo_hint**

---

## Rules (from README §11 Branch Creation Policy)

- Work branches use the **bare Jira key as prefix** — NO `feature/` or `bugfix/` prefix
- Only `hotfix/*` uses a prefix
- Pattern: `{JIRA-KEY}-{description}` (e.g. `ELS-123-add-login-with-google`)
- Description: lowercase kebab-case, specific (not `fix-bug`, not `update-code`)
- **Always branched from latest `master`** — never from develop/staging/other branch
- Jira ticket must exist and be linked

---

## Interaction convention — ALWAYS use AskUserQuestion

**Do NOT print numbered options as text and wait for the user to type a number.** Every time this skill needs user input, call the `AskUserQuestion` tool so the user can select with arrow keys / click.

Rules when calling `AskUserQuestion`:
- `header`: ≤12 chars, chip-style label (e.g. `"Description"`, `"Dirty tree"`)
- `options`: 2–4 items, mutually exclusive unless `multiSelect: true`
- Do NOT add an "Other" option — the tool adds it automatically for free-text input
- First option is the recommended/safest choice — suffix label with `" (Recommended)"` when appropriate
- Destructive options go last, with description starting with `"IRREVERSIBLE: "`
- Always provide a Cancel option when the action is non-trivial
- Multiple independent questions in the same step → pass them together in ONE `AskUserQuestion` call (max 4 questions), so the user answers in one UI pass

---

## Workflow

### Step 1 — Parse & validate arguments

Extract:
- `jira_key` from first `^[A-Z]+-[0-9]+$` token or Jira URL (regex against `browse/([A-Z]+-[0-9]+)`)
- `description` from kebab-case tokens (if any)
- `repo_hint` from GitHub/Bitbucket URLs or repo names (e.g. `mcp-ohmyhotel`, `tomomh/reactjs`)

Validations (reject immediately, do NOT prompt to fix):
- `jira_key` matches `^[A-Z]+-[0-9]+$` — if missing, stop with: *"Jira key missing or invalid. Expected ELS-123, OMH-4857, or a Jira URL."*
- If `description` is provided: must match `^[a-z0-9][a-z0-9-]*[a-z0-9]$` and not be in `["fix-bug", "update-code", "wip", "temp", "test"]`
- Full branch name length ≤ 80 chars

If `description` is missing, skip to Step 2 (we need the Jira summary to suggest candidates).

### Step 2 — Verify Jira ticket exists

Call `mcp__mcp-atlassian__jira_get_issue(issue_key=jira_key)`.

- If not found → stop with *"Jira ticket {jira_key} not found"*
- Extract: `summary`, `issue_type`, `status`, `assignee`

Show a brief one-line confirmation to the user (no prompt yet):
> **ELS-1000** — "[demo] Test skill git branch strategy" · Task · To Do · Tom

If status is `Done` or `Closed`, add a question for Step 3 bundle:

```
AskUserQuestion question:
  question: "Ticket is already {status}. Proceed?"
  header:   "Closed tkt"
  options:
    - label: "Cancel" (Recommended) — description: "Don't create branch; pick a different ticket"
    - label: "Proceed anyway" — description: "Reopen work on a closed ticket"
```

### Step 3 — Gather missing inputs in a single AskUserQuestion call

Build the list of questions to ask (up to 4). Include only the ones that are actually needed:

**Q1 — Description** (only if missing):
Generate 3 kebab-case candidates from the Jira summary. Example heuristics:
- Candidate A: shortest meaningful phrase (2–3 words)
- Candidate B: tool/feature-specific (keywords from summary)
- Candidate C: outcome/action-focused

```
question: "Choose a branch description"
header:   "Description"
options:
  - label: "<candidate-A>" — description: "short, general"
  - label: "<candidate-B>" — description: "specific focus"
  - label: "<candidate-C>" — description: "outcome-focused"
  # User can pick "Other" to type a custom kebab-case value (tool adds this)
```

Validate the user's choice (or custom input) against the kebab-case regex — if invalid, re-prompt with the same question plus an error note prepended to the question text.

**Q2 — Repo target** (only if `repo_hint` is provided and differs from current cwd):

Probe filesystem:
- If hint is a GitHub/Bitbucket URL → the repo may not be cloned yet
- If hint is a bare name → check `../{name}`, `D:/Github/{name}`, sibling dirs

```
question: "Target repo doesn't match current directory. What to do?"
header:   "Repo target"
options:
  - label: "Stay here" (Recommended) — description: "Create branch in current repo: {cwd}"
  - label: "Switch to {found-path}" — description: "cd to existing local clone"  # only if found
  - label: "Clone {url} first" — description: "git clone to D:/Github/{name}, then cd"  # only if URL given
  - label: "Cancel" — description: "I'll navigate manually"
```

**Q3 — Dirty working tree** (only if `git status --porcelain` returns non-empty):

Show the first 10 dirty files in the question text (e.g. `"3 modified, 2 untracked: README.md, .claude/..."`).

```
question: "Working tree has uncommitted changes. Handle how?"
header:   "Dirty tree"
options:
  - label: "Cancel" (Recommended) — description: "I'll commit/stash manually then retry"
  - label: "Stash" — description: "git stash push -u (restore later with git stash pop)"
  - label: "Commit first" — description: "Triggers /omh-commit before creating branch"
  - label: "Discard all" — description: "IRREVERSIBLE: git checkout . && git clean -fd"
```

If the user picks "Discard all", ask a **follow-up confirmation** as a separate `AskUserQuestion` call:
```
question: "Really discard all local changes? This cannot be undone."
header:   "Confirm"
options:
  - label: "Cancel" (Recommended) — description: "Keep changes"
  - label: "Yes, discard" — description: "IRREVERSIBLE"
```

**Call `AskUserQuestion` once** with Q1+Q2+Q3 bundled (only the ones that apply).

### Step 4 — Execute

After all inputs are confirmed:

```bash
git fetch origin master
git checkout -b {JIRA-KEY}-{description} origin/master
```

Rules:
- Never create from current HEAD — always from `origin/master`
- Never create from `develop` or `staging`
- If `git checkout -b` fails because branch exists → stop, report, do NOT auto-delete or force

### Step 5 — Report

Print:
- **Jira**: `{jira_key}` — `{summary}`
- **Branch**: `{JIRA-KEY}-{description}`
- **Based on**: `origin/master @ <short-sha>`
- **Repo**: `{cwd}`
- **Next**: implement → `/omh-commit` → `/omh-open-pr`

---

## Error handling

- **Not a git repo**: stop with clear message
- **Fetch fails (no network)**: stop — do not create branch from stale master
- **Branch already exists**: stop — do not checkout or force
- **Jira MCP unavailable**: use `AskUserQuestion` with options `["Cancel", "Proceed without Jira verification"]` — default is Cancel

---

## What this skill does NOT do

- Does not merge to develop (§6 — direct merge, no PR required)
- Does not create PR (use `/omh-open-pr`)
- Does not reset develop/staging (use `/omh-reset-develop` / `/omh-reset-staging`)
- Does not create hotfix branches (use `/omh-hotfix` — different rules per §10)

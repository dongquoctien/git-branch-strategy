# Open Pull Request to a Specified Branch (escape hatch, off-workflow)

**Usage**: `/omh-open-pr-to <target-branch>`

Examples:
- `/omh-open-pr-to develop` — direct PR into develop (off-workflow shortcut)
- `/omh-open-pr-to staging` — direct PR into staging
- `/omh-open-pr-to release/v1.4.0-payment` — direct PR into a release branch
- `/omh-open-pr-to ELS-234-add-dark-mode` — PR into another work branch
- `/omh-open-pr-to master` — refused, redirects to `/omh-open-pr`

Parse arguments from: $ARGUMENTS
- Required: target branch. If omitted → `AskUserQuestion` to pick.

---

## Scope — this skill is OFF the standard workflow

This skill is an **escape hatch**. It does not enforce the Git Branch Strategy. It exists for ad-hoc situations where an engineer needs to open a PR into a non-master branch and the standard skills (`/omh-open-pr`, `/omh-cherry-pick`, `/omh-release`, the throwaway-branch merges in §6/§8) don't fit.

What this means:

- **The only forbidden target is `master`** — that flow lives in `/omh-open-pr` and must stay there (§15).
- **All other targets are allowed**: `develop`, `staging`, `release/*`, hotfix/*, another work branch, anything.
- **No rebase. No reset.** The source branch is **not** rebased onto the target and is **not** reset to match the target. The whole point is to preserve the source so it can later be PR'd onto master via `/omh-open-pr`.
- **No §13 PR body template.** Title and body come straight from the commit(s) the user selects — same content as the commit.
- **No Jira lookup, no auto-link.** This is a thin wrapper around the host's PR-create API.

If you want strategy-enforced flows, use the right skill instead:

| Goal | Use |
|---|---|
| PR onto master | `/omh-open-pr` (§15) |
| Bug into a release branch | `/omh-cherry-pick` (§9 upstream-first) |
| Cut a release | `/omh-release` (§7) |
| Hotfix from prod tag | `/omh-hotfix` (§10) |
| Test feature on develop without a PR | `git merge` into develop directly (§6) |

`/omh-open-pr-to` is for everything else.

---

## Why source is never rebased/reset onto target

The source branch was cut from master. The user will eventually PR it onto master via `/omh-open-pr`. If this skill rebased source onto `develop`, `staging`, or `release/*`, source would absorb code that hasn't reached master yet — that code would then ride along to master at PR time, which the strategy forbids.

So this skill keeps the source branch exactly as the user left it. Conflicts with the target (if any) are surfaced as informational warnings; the user / reviewer / target maintainer resolves them on the host side. The skill never rewrites source history.

---

## Interaction convention — ALWAYS use AskUserQuestion

Do NOT print numbered text options. Every prompt uses `AskUserQuestion`.

Rules:
- `header`: ≤12 chars chip label
- 2–4 options; first option is safest/recommended (suffix `" (Recommended)"`)
- Do NOT add "Other" — the tool adds it automatically for free-text
- Destructive options last; description starts with `"IRREVERSIBLE: "`
- Bundle independent questions in one call (max 4)

---

## Workflow

### Step 1 — Resolve target & dispatch

Read `<target-branch>` from `$ARGUMENTS`. If missing, prompt:

```
AskUserQuestion:
  question: "Target branch for this PR?"
  header:   "Target"
  multiSelect: false
  options:
    - "develop" (Recommended) — description: "PR into develop"
    - "staging" — description: "PR into staging"
    - "Another branch" — description: "Type the branch name via Other"
    - "Cancel" — description: "Exit skill"
```

**Dispatch — the only hard refusal:**

| Target value | Action |
|---|---|
| `master` | **Redirect.** Print: *"Target `master` is the standard flow — use `/omh-open-pr` instead. Exiting."* Stop. |
| Anything else | Continue to Step 2. |

No other refusals. Targets like `develop`, `staging`, `release/*` are allowed — this skill is the off-workflow escape hatch.

### Step 2 — Pre-checks (minimal)

Run:
```bash
git branch --show-current
git status --porcelain
git ls-remote --exit-code --heads origin <target>
git fetch origin <target>
git log origin/<target>..HEAD --oneline
```

Stop conditions:

- **Source = `master`** — refuse: *"PR'ing FROM master is not the purpose of this skill. Cut a work branch first."* (This is the only source restriction. Source = `develop` / `staging` / `release/*` is allowed — unusual, but allowed.)
- **Source = target** — refuse: *"Source and target are the same branch."*
- **Working tree dirty** — refuse: *"Working tree has uncommitted changes. Commit or stash before opening PR."* Do NOT auto-stash.
- **Target not on remote** — refuse: *"`origin/<target>` not found. Push or create it first, or check spelling."*
- **Source has 0 commits ahead of target** — refuse: *"Nothing to PR — `<source>` is not ahead of `<target>`."*

That's it. No rebase check, no master-currency check, no Jira validation.

### Step 3 — Pick the commit(s) for title + body

List commits ahead of target:

```bash
git log origin/<target>..HEAD --pretty=format:"%h %s"
```

Then ask:

```
AskUserQuestion:
  question: "Which commit's content should become the PR title + body?"
  header:   "PR source"
  multiSelect: false
  options:
    - "Latest commit (HEAD)" (Recommended) — description: "<HEAD-short-sha> <HEAD-subject>"
    - "Pick a specific commit" — description: "List all <N> commits ahead; user picks one"
    - "Combine all commits" — description: "Title = HEAD subject; body = concatenated subject+body of every commit ahead"
    - "Cancel" — description: "Exit skill"
```

Resolve the choice:

- **Latest commit (HEAD)** — title = subject of HEAD; body = body of HEAD (everything after the first blank line in `git log -1 --pretty=format:%B`).
- **Pick a specific commit** — second `AskUserQuestion` listing each commit ahead as an option (`<short-sha> <subject>`). After pick, title = subject of that commit; body = body of that commit.
- **Combine all commits** — title = subject of HEAD; body = for each commit ahead (oldest → newest), append a block:
  ```
  ### <short-sha> <subject>
  <body of that commit, or empty>
  ```
- **Cancel** — stop.

If the chosen commit has no body, body is left empty. Do NOT fabricate a summary, test plan, risk, promotion path, or any §13 field. Title + body are commit content, verbatim.

### Step 4 — Show preview & confirm

Print:
```
──────────────────────────────────────
Source:    <source-branch>
Target:    <target>
Commits:   <N> ahead of <target>
Mode:      <head | picked <sha> | combined>
──────────────────────────────────────
Title:
  <title>

Body:
  <body, or "(empty — chosen commit has no body)">
──────────────────────────────────────
```

Then:

```
AskUserQuestion:
  question: "Create this PR?"
  header:   "Create PR"
  options:
    - "Create as shown" (Recommended) — description: "Push source if needed and open PR"
    - "Re-pick commit" — description: "Go back to Step 3"
    - "Cancel" — description: "Don't create PR"
```

If user picks **Re-pick commit**, loop back to Step 3. After re-pick, re-render preview.

### Step 5 — Push source branch

```bash
git push -u origin <source-branch>
```

- If already pushed and up-to-date → skip.
- If already pushed and diverged → ask the user; do NOT auto force-push.
- If push fails → surface the error, stop.

### Step 6 — Create the PR

Detect remote from `git remote get-url origin`:

**Bitbucket (`ohmyhotel` workspace):**
```
mcp__bitbucket__createPullRequest(
  workspace="ohmyhotel",
  repo_slug=<repo>,
  title=<title>,
  sourceBranch=<source>,
  targetBranch=<target>,
  description=<body>
)
```

**GitHub:**
```bash
gh pr create --base <target> --head <source> --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

If body is empty, pass an empty string — do not fabricate content.

### Step 7 — Report

Output:
- **Source**: `<source-branch>`
- **Target**: `<target>`
- **Mode**: `<head | picked <sha> | combined>`
- **Title**: `<pr-title>`
- **PR URL**: `<url>`
- **Note**: *"Source branch was not rebased or reset. It is still master-based and can later be PR'd to master via `/omh-open-pr`."*

---

## Error handling

- **PR already exists for `<source>` → `<target>`** — surface the existing PR URL and offer to update the description with the new title+body. Do not open a duplicate.
- **MCP Bitbucket / `gh` CLI unavailable** — print the title + body block and the host's create-PR URL, ask the user to paste manually.
- **Push rejected (non-fast-forward)** — ask the user to investigate. Do NOT force-push.

---

## Hard refusals

- Do NOT open PR targeting `master` — redirect to `/omh-open-pr`.
- Do NOT open PR FROM `master` as source.
- Do NOT rebase the source branch onto the target.
- Do NOT reset the source branch to the target.
- Do NOT auto-stash, auto-rebase, auto-resolve conflicts, or auto force-push.
- Do NOT fabricate PR body content (summary, test evidence, risk, promotion path, Jira link). Body = commit content, verbatim.
- Do NOT inject an AI-assistant attribution line into the title or body (`Co-Authored-By: Claude...`, `🤖 Generated with...`) — forbidden by §13. Body stays verbatim commit content, which §14 already keeps trailer-free.
- Do NOT use `--force` (use `--force-with-lease` only if explicitly asked), `--no-verify`, or `--amend` unless the user explicitly requests it.

---

## What this skill does NOT do

- Does not enforce §6 / §8 / §9 / §13 / §15 — use the dedicated skills for those flows.
- Does not handle PR to master — that's `/omh-open-pr`.
- Does not cherry-pick — that's `/omh-cherry-pick`.
- Does not validate Jira, derive risk, suggest promotion path, or generate test evidence.
- Does not rebase or reset source — source stays exactly as the user left it.
- Does not run CI locally — CI runs on the host after push.
- Does not approve, request reviewers, or merge.

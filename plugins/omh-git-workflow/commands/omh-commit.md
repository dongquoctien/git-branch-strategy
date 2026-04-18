# Create Commit (OMH Git Strategy §14)

**Usage**: `/omh-commit [message hint]`

Example: `/omh-commit add Google OAuth login`

Parse arguments from: $ARGUMENTS — used as an optional hint for the subject line. If empty, infer the subject from staged changes.

---

## Rules (from README §14 Git Commit Convention)

**Format:**
```
<type>(<scope>): <subject>          ← subject line: 50 chars or less
                                    ← blank line (mandatory)
<body>                              ← body: wrap at 72 chars per line
                                    ← blank line (optional)
<footer>                            ← footer: issue refs, breaking changes
```

**Valid types:** `feat`, `fix`, `refactor`, `infra`, `hotfix`, `docs`, `test`, `other`

**Valid scopes** (pick the one that matches the changed area):
`auth`, `payment`, `search`, `booking`, `infra`, `ui`, `api`, `notification`

If the change does not match any listed scope, pick a new lowercase single-word/hyphenated scope that identifies the affected module — do NOT use the Jira project key.

---

## Hard rules

| Rule | Check |
|---|---|
| Subject ≤ 50 chars | Count chars of the full line including `type(scope): ` |
| Subject imperative mood | "add", "fix", "remove" — NOT "added", "fixes", "adding" |
| Subject no trailing period | Last char of subject ≠ `.` |
| Subject lowercase after type/scope | First char of `<subject>` after `: ` is lowercase |
| Body wrapped at 72 chars | Every body line ≤ 72 chars |
| Blank line between subject and body | Mandatory if body exists |
| `hotfix/*` branch uses `fix` commit type | Do NOT use `hotfix` type for hotfix branches — per §14 note |

**Reject vague subjects:** `fix bug`, `update code`, `WIP`, `changes`, `misc`, `stuff`.

---

## Workflow

### Step 1 — Inspect state

Run in parallel:
```bash
git status --porcelain
git diff --staged
git diff
git log -5 --oneline
git branch --show-current
```

- If nothing is staged AND nothing is modified → stop, "nothing to commit"
- If nothing is staged but files are modified → call `AskUserQuestion` (do NOT auto `git add -A`):

  Show file list (max 10) in the question text, e.g. *"4 modified, 1 untracked: README.md, .claude/..., src/foo.ts, ..."*

  ```
  AskUserQuestion:
    question: "No files staged. How to stage?"
    header:   "Stage"
    multiSelect: false
    options:
      - label: "Stage specific files" (Recommended) — description: "I'll pick files via multi-select next"
      - label: "Stage ALL" — description: "git add -A — review first for secrets (.env, credentials)"
      - label: "Cancel" — description: "I'll stage manually then re-run"
  ```

  If user picks "Stage specific files", immediately call `AskUserQuestion` again with `multiSelect: true` listing the files as options (up to 4; if more than 4, fall back to "Stage ALL" or Cancel prompt with warning).

- Extract current branch name — used for Jira footer

### Step 2 — Derive type and scope

From the staged diff:
- New feature files, added public APIs → `feat`
- Bug fix (references an existing behavior) → `fix`
- Pure internal restructuring, no behavior change → `refactor`
- CI/CD, Dockerfile, deployment configs → `infra`
- `*.md`, comments only → `docs`
- `*.test.*`, `*.spec.*`, test utilities → `test`

Scope = the primary module touched. If multiple, pick the most impacted one. If genuinely cross-cutting, use `other` as type with no scope: `other: <subject>`.

### Step 3 — Derive subject

- Use the user's hint if provided, otherwise summarize the diff
- Imperative mood: rewrite "Added X" → "add X", "Fixed Y" → "fix Y"
- Strip trailing period
- Lowercase first letter after `: `
- Count chars of full line: `<type>(<scope>): <subject>`. If > 50, shorten the subject. Never split across lines.

### Step 4 — Derive body (only if the change needs it)

Include a body when:
- The **why** is non-obvious from the diff
- There is a breaking change
- Multiple logical changes are bundled (list them)

Skip the body for trivial commits (typo fix, dep bump, single-line change).

Wrap every line at 72 chars. Use `- ` bullets when listing multiple points.

### Step 5 — Derive footer

Extract Jira key from current branch name:
- Work branch `ELS-123-description` → `Refs: ELS-123`
- Hotfix branch `hotfix/OMH-4857-desc` → `Refs: OMH-4857`
- No Jira key in branch name → warn user, ask for ticket

If breaking change detected (removed API, schema change, env var removal), add:
```
BREAKING CHANGE: <short description>
```

### Step 6 — Show commit preview & confirm via AskUserQuestion

Print the commit preview as a fenced block first (for readability), then call `AskUserQuestion`.

Preview block:
```
<type>(<scope>): <subject>

<body>

Refs: <JIRA-KEY>
```
Also print: *"Subject: N/50 chars ✅"* (or ⚠️ if over).

Then call `AskUserQuestion` (do NOT auto-commit):

```
AskUserQuestion:
  question: "Commit with this message?"
  header:   "Commit"
  multiSelect: false
  options:
    - label: "Commit as shown" (Recommended) — description: "Run git commit with the preview above"
    - label: "Change type/scope" — description: "Pick different conventional type or scope"
    - label: "Edit subject/body" — description: "Rewrite the message (Other → type new text)"
    - label: "Cancel" — description: "Don't commit"
```

If user picks "Change type/scope", call `AskUserQuestion` with two questions bundled:
- Q1 type: `feat | fix | refactor | infra` (use multiSelect: false; user picks Other for `docs`/`test`/`other`)
- Q2 scope: `auth | payment | search | booking` (use Other for `ui`/`api`/`notification`/custom)

If user picks "Edit subject/body", call `AskUserQuestion` again to let them choose which to edit:
- `label: "Subject"` / `label: "Body"` / `label: "Both"` — then rely on Other/free-text for the new value.

After every edit, re-show the preview and re-prompt with the same confirm question.

### Step 7 — Commit

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <subject>

<body>

Refs: <JIRA-KEY>
EOF
)"
```

Never use `--no-verify` unless user explicitly requests it.
Never use `--amend` unless user explicitly requests it — create a new commit instead.

### Step 8 — Verify

```bash
git log -1 --format="%s%n%n%b"
```

Show the committed message back to the user.

---

## Interaction convention — ALWAYS use AskUserQuestion

Do NOT print numbered text options. Every prompt uses the `AskUserQuestion` tool so the user clicks / arrow-keys to select.

Rules:
- `header`: ≤12 chars chip label
- 2–4 options; first option is safest/recommended (suffix `" (Recommended)"`)
- Do NOT add "Other" — tool adds it automatically for free-text
- Destructive options last, description starts with `"IRREVERSIBLE: "`
- Bundle independent questions in one call (max 4) so user answers in one UI pass

## Error handling

- **Pre-commit hook fails**: do NOT retry with `--no-verify`. Surface the hook output, let user decide how to fix. After fixing, create a NEW commit (not amend).
- **Detached HEAD**: stop, warn user — this commit would be orphaned
- **Committing on master directly**: stop, refuse — per §22, direct push to master is forbidden
- **Committing on develop/staging**: warn user — these are throwaway branches, work should happen on a `{JIRA-KEY}-*` branch

---

## Quick reference (validated subjects)

```
feat(payment): add Apple Pay support        ← 42 chars ✅
fix(booking): resolve session timeout       ← 39 chars ✅
refactor(search): extract filter utilities  ← 43 chars ✅
infra(deploy): add SonarQube quality gate   ← 43 chars ✅
docs(api): update booking endpoint docs     ← 42 chars ✅
```

## What this skill does NOT do

- Does not stage files automatically via `-A` (user must stage explicitly)
- Does not push (that's a separate step)
- Does not create PR (use `/omh-open-pr`)
- Does not bypass CI or hooks

# Open Pull Request to master (OMH Git Strategy §13, §15)

**Usage**: `/omh-open-pr [target-branch]`

Example: `/omh-open-pr` (defaults to `master`)

Parse arguments from: $ARGUMENTS
- Optional: target branch (default `master`)

---

## Rules (from README §13 PR Standards + §15 PR Policy)

**All PR fields are MANDATORY — reviewers must reject PRs missing any field.**

| Field | Required | Notes |
|---|---|---|
| Title | Always | Format: `<type>(scope): description` — conventional commit |
| Summary | Always | 2–5 sentences, what changed and WHY (not how) |
| Changed files / components | Always | List affected services/modules |
| Test evidence | Always | Screenshots, test output, or manual steps |
| Risk level | Always | Low / Medium / High |
| Jira ticket(s) | Always | Linked ticket — PR blocks without it |
| Rebase confirmation | Always | Branch must be rebased onto latest master |
| Pipeline progress file | Always | `work/features/.progress/<jira-key>.json` committed on the branch — see Step 1b |
| Rollback plan | High risk only | Required when risk = High |
| Migration notes | DB/infra only | For schema/index/infra changes |

**Approval requirements:**
- Work branch → master: 2 approvals (must include Tech Lead)
- Hotfix → master: 1 approval (must be Tech Lead)
- develop: no PR required (direct merge per §6)

**Hard gates before merge:** Build, Unit tests (≥70% coverage), Lint, SonarQube gate.

---

## Workflow

### Step 1 — Inspect branch state

Run in parallel:
```bash
git branch --show-current
git status --porcelain
git log origin/master..HEAD --oneline
git diff origin/master...HEAD --stat
git fetch origin master
git rev-list --count HEAD..origin/master
```

Checks:
- Current branch is NOT `master`, `develop`, `staging`, `release/*` — if it is, stop
- Working tree is clean — if not, stop, tell user to commit first
- Branch has at least 1 commit ahead of master — if 0, stop, "nothing to PR"
- Branch name matches `{JIRA-KEY}-*` or `hotfix/{JIRA-KEY}-*` — else warn

Extract:
- Jira key from branch name
- Commit list (for summary generation)
- Files changed (for "changed components" field)

### Step 1b — Require the pipeline progress file

**Every PR must carry `{workDocDir}/.progress/<jira-key>.json`** (`workDocDir` defaults to
`work/features`; read `.claude/backend-webflux-plugin.json` if the repo has one). It is the record
the company grades the ticket on, so a PR without it is incomplete regardless of how small the
change is. The rule covers **every target** — `master` here, and `staging` / `develop` through
`/omh-open-pr-to`, which runs the same check as one of its Step 2 stop conditions.

Check whether the branch has one:

```bash
JIRA_KEY_LC=$(echo "<JIRA-KEY>" | tr 'A-Z' 'a-z')
git diff origin/<target-branch>...HEAD --name-only | grep -E "\.progress/${JIRA_KEY_LC}\.json$"
ls work/features/.progress/${JIRA_KEY_LC}.json 2>/dev/null
```

- **Committed on the branch** → continue; list it in *Changed files / components* (Step 4).
- **Exists but not committed** → stop, tell the user to stage and commit it. Do not `git add` it
  yourself (§ no silent auto-fixes).
- **Does not exist** → the change never ran the `be-*` pipeline. Build one now, do **not** skip the
  field and do **not** open the PR without it.

**No exemption — a SQL-only migration records its review instead of a build.** When the diff is
`.sql` files under `migration/**` and nothing else (`/omh-voc-migration` says so, and the diff is
checked before it is believed), the file still has to exist: the change is graded on the Claude AI
SQL Review of SOP §3, not on a build. Write it with `source: "sql-review"`, replacing `build` with
a `sqlReview` block copied from the review the skill already produced:

```json
"sqlReview": {
  "riskLevel": "Medium",
  "indexUsed": "Yes",
  "fullScan": "No",
  "lockRisk": "Low",
  "estimatedRows": 463,
  "recommendation": "Safe to execute",
  "heavyOp": false,
  "idempotent": true,
  "reviewedAt": "2026-10-19T09:28:00Z"
}
```

Every value is copied from that review block, never re-judged here to fill the file in — the same
rule as `build.result`. If the review has not been run yet, the PR is not ready: run it first. A
diff that touches anything outside `migration/**` `.sql` is an ordinary change and takes
`source: "manual"` with a real `build`.

Also confirm `.progress/.lock` is **not** in the diff — it is a per-run lock, never committed. If
it is, stop and tell the user to remove it from the commit.

#### Building the file for a change that never ran the pipeline

Write `work/features/.progress/<jira-key>.json` with `source: "manual"` (schema:
`backend-webflux-plugin/templates/progress-schema.md` § Optional Fields). Derive every field from
what is actually in the branch:

| Field | Where it comes from |
|---|---|
| `feature` | the Jira key, lowercase — `els-4075` |
| `source` | `"manual"` |
| `createdAt` / `updatedAt` | `date -u +%Y-%m-%dT%H:%M:%SZ` |
| `pipeline.status` | `"implemented"` |
| `pipeline.filesModified` | `git diff origin/<target-branch>...HEAD --name-only` |
| `pipeline.build.command` | the test/build command actually run for this change |
| `pipeline.build.result` | `PASS` / `FAIL` / `NOT_RUN` — see below |
| `pipeline.build.timestamp` | when that command ran |

Omit `scenarios` and `workDocument` — a manual change has no work document, and `0 / 0` would read
as a feature with no tests rather than one that never had scenarios.

**`result` is evidence, not a formality.** Write `PASS` only for a command you ran and watched
succeed. Nothing was run — no JDK here, the module's suite is not runnable in this session, the
user has not run it yet — then it is `NOT_RUN` plus a `note` saying why:

```json
"build": {
  "command": "./gradlew :web-api:test --tests com.oh.api.FooTest",
  "result": "NOT_RUN",
  "note": "no JDK on this machine; build not executed",
  "timestamp": "2026-10-19T04:09:40Z"
}
```

Never invent a `PASS`. The file is read as test evidence by reviewers, it is graded, and it lives
in git history permanently — a fabricated pass is a false verification record, not a placeholder.
`NOT_RUN` with a reason is always the correct answer when nothing ran.

Show the file content and confirm before writing it:

```
AskUserQuestion:
  question: "No progress file on this branch. Create work/features/.progress/<jira-key>.json?"
  header:   "Progress"
  multiSelect: false
  options:
    - label: "Create as shown" (Recommended) — description: "Write the file, then stage and commit it with the PR"
    - label: "Edit build result" — description: "Change the command, result, or note"
    - label: "Cancel" — description: "Stop — the PR cannot be opened without it"
```

### Step 2 — Verify rebase status

```bash
git rev-list --count HEAD..origin/master
```

- If count > 0 → branch is behind master. **Stop** and tell user:
  > "Branch is N commits behind master. Rebase first: `git rebase origin/master`, resolve conflicts, then re-run."
- Do NOT auto-rebase (may have conflicts).

### Step 3 — Fetch Jira ticket details

```
mcp__mcp-atlassian__jira_get_issue(issue_key=<extracted-key>)
```

Extract:
- Summary (for PR title suggestion)
- Issue type → maps to commit type: Bug → `fix`, Story/Task → `feat`, Improvement → `refactor`
- Description (for PR summary context)

If no Jira key in branch name or ticket not found → stop, ask user to provide ticket.

### Step 4 — Derive PR fields

**Title** — conventional commit format:
- Use the type of the most recent commit, OR derive from Jira issue type
- Scope = primary touched module (see §14 scope list: `auth`, `payment`, `search`, `booking`, `infra`, `ui`, `api`, `notification`)
- Subject from Jira summary, rewritten in imperative mood, lowercase, no trailing period
- Example: `feat(auth): add Google OAuth login`
- **VOC override**: if the caller passes an explicit title (e.g. `/omh-voc-migration` supplies
  `VOC(<JIRA-KEY>): …`), use it verbatim — do NOT re-derive a conventional-commit title. VOC /
  data-migration PRs use the `VOC(<JIRA-KEY>):` prefix and also get the `VOC` repo label (Step 7).

**Summary** (2–5 sentences):
- What changed + why (business impact / user-facing reason)
- Reference the Jira ticket context
- Do NOT explain how the code works

**Changed files / components**:
- Group files by service/module
- Format: `- <service>: <files or component names>`

**Test evidence** — call `AskUserQuestion` (do NOT ask open-ended):

```
AskUserQuestion:
  question: "What test evidence do you have? (mandatory per §13)"
  header:   "Test evid"
  multiSelect: true
  options:
    - label: "Unit test output" (Recommended) — description: "I run the test suite now and capture output"
    - label: "CI build link" — description: "Paste URL via Other"
    - label: "Manual test steps" — description: "Describe steps taken (Other for free-text)"
    - label: "Screenshots" — description: "Embed images in the PR body (local files or Jira attachments)"
```

Note: if user picks nothing / only "Other: none available" → flag the PR body as *"⚠️ Test evidence: pending — requires Tech Lead sign-off per §13"*. Never fabricate evidence.

#### Step 4b — Embed screenshots (only if "Screenshots" was chosen)

GitHub has no official API for attaching images to a PR body, so use the bundled
helper, which drives the same `uploads.github.com` endpoint the web UI uses:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/pr-attach-images.sh --help
```

**GitHub only.** If `origin` is Bitbucket the script exits 1 with a warning — that is
expected. Fall back to attaching the images to the Jira ticket and linking it from the
*Test evidence* section; do not try to work around it.

**Always confirm before uploading** — the upload is outward-facing and cannot be undone
from the CLI. Ask where the images come from:

```
AskUserQuestion:
  question: "Where should the screenshots come from?"
  header:   "Screenshots"
  multiSelect: false
  options:
    - label: "From the Jira ticket" (Recommended) — description: "Pull image attachments off <JIRA-KEY> and embed them"
    - label: "Local files" — description: "Give paths (e.g. from /tom-dev-flow:tom-snapshot); paste via Other"
    - label: "Both" — description: "Jira attachments plus local files"
    - label: "Skip images" — description: "Use text evidence only"
```

Then preview with `--dry-run` and show the user the exact file list before uploading:

```bash
# Jira attachments (needs JIRA_URL / JIRA_USERNAME / JIRA_API_TOKEN in env)
"${CLAUDE_PLUGIN_ROOT}/scripts/pr-attach-images.sh" \
  --jira <JIRA-KEY> --width 700 --title "Test evidence" --dry-run

# Local files
"${CLAUDE_PLUGIN_ROOT}/scripts/pr-attach-images.sh" \
  --width 700 --title "Test evidence" --dry-run shot1.png shot2.png
```

Confirm the list, then re-run **without** `--dry-run` and capture stdout:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/pr-attach-images.sh" \
  --jira <JIRA-KEY> --width 700 --title "Test evidence" > /tmp/evidence.md
```

Paste that Markdown into the *Test evidence* section of the PR body.

Notes:
- `--width 700` keeps screenshots readable without dominating the page; GitHub derives
  the height, so aspect ratio is preserved. Omit `--width` for full size.
- `--jira-only a.png,b.png` narrows which attachments are taken; without it every image
  on the ticket is pulled. Prefer naming them — QA tickets often carry dozens.
- Images render for logged-out viewers, so external reviewers can see them.
- Progress goes to stderr and Markdown to stdout, so redirecting gives a clean fragment.
- If the script exits 2, the upload endpoint failed. It is undocumented and may have
  changed — do NOT retry in a loop. Fall back to linking the Jira ticket, and tell the
  user the endpoint appears to be broken.

**Risk level** — infer a default, confirm via `AskUserQuestion`:

Print the inferred level and reason first (e.g. *"Inferred: Medium — touches shared `auth/` utilities"*), then:

```
AskUserQuestion:
  question: "Confirm risk level"
  header:   "Risk"
  multiSelect: false
  options:
    - label: "Keep inferred (<X>)" (Recommended) — description: "Use the auto-inferred level"
    - label: "Low" — description: "Isolated, single module, easily reverted"
    - label: "Medium" — description: "Shared utilities, multiple modules, external deps"
    - label: "High" — description: "Cross-service, DB migration, auth/payment/booking core — requires rollback plan"
```

- **Low**: single module, no shared deps, easily revertible
- **Medium**: touches shared utilities, multiple modules, external service calls
- **High**: cross-service, DB migration, auth/payment/booking core, or hard to revert

Triggers for High automatically:
- Any file in `auth/`, `payment/`, `booking/` critical paths
- Any `*.sql`, migration files, schema changes
- Any change in `infra/`, CI/CD configs
- Dependency version bumps on core libs

**Rollback plan** (if High): ask user to describe how to revert. Do NOT auto-generate.

**Migration notes** (if DB/infra): ask user for:
- Estimated run time
- Zero-downtime status
- Rollback SQL / procedure

### Step 5 — Show PR preview & confirm via AskUserQuestion

Print the full PR body first as a readable block:
```
──────────────────────────────────────
Title:  <title>
Target: <branch>  |  Source: <branch>
Risk:   <Low|Medium|High>
──────────────────────────────────────
<body preview>
──────────────────────────────────────
```

Then call `AskUserQuestion`:

```
AskUserQuestion:
  question: "Create this PR?"
  header:   "Create PR"
  multiSelect: false
  options:
    - label: "Create as shown" (Recommended) — description: "Push branch and open PR now"
    - label: "Edit title/summary" — description: "Revise PR title or summary text"
    - label: "Change risk or add plan" — description: "Change risk level or add rollback/migration notes"
    - label: "Cancel" — description: "Don't create PR"
```

Handle the sub-flows:
- **Edit title/summary** → `AskUserQuestion` with options `["Title", "Summary", "Both"]`, then free-text via Other
- **Change risk or add plan** → `AskUserQuestion` with options `["Risk level", "Rollback plan", "Migration notes", "All of these"]`
- Always re-show preview and re-prompt until user picks "Create as shown" or "Cancel"

Template:
```markdown
## Summary
<2–5 sentences>

## Changed files / components
- <service>: <components>
- work/features/.progress/<jira-key>.json: pipeline progress (<pipeline|manual|sql-review> source)

## Jira
<JIRA-KEY>: <ticket-summary-link>

## Test evidence
<screenshots / test output / manual steps>

## Risk level
<Low | Medium | High> — <justification>

## Rebase confirmation
✅ Branch rebased onto latest master as of <YYYY-MM-DD>

<!-- High-risk PRs only -->
## Rollback plan
<how to revert>

<!-- DB/infra changes only -->
## Migration notes
- Estimated run time: <X>
- Zero-downtime: <yes/no>
- Rollback: <SQL or procedure>
```

The PR body ends here. **Never** append an AI-assistant attribution line —
no `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`,
no `🤖 Generated with Claude Code`, no equivalent tool footer (§13 "No AI /
tool attribution in the PR body").

### Step 6 — Push branch

```bash
git push -u origin <branch-name>
```

- If branch already pushed and diverged → ask user. Do NOT auto force-push.
- If up-to-date → skip push, proceed.

### Step 7 — Create the PR

**Detect remote** (Bitbucket vs GitHub) from `git remote get-url origin`:

**Bitbucket (ohmyhotel workspace):**
```
mcp__bitbucket__createPullRequest(
  workspace="ohmyhotel",
  repo_slug=<repo>,
  title=<title>,
  sourceBranch=<current-branch>,
  targetBranch=<target>,
  description=<body>
)
```

**GitHub:**
```bash
gh pr create --base <target> --head <branch> --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

**Apply PR labels (if any were requested by the caller):** e.g. for a VOC / data-migration PR add
the `VOC` label right after creation —
```bash
gh pr edit <pr-number> --add-label VOC
```
(label `VOC` exists on `ohmyhotelco/oh-api`, color `F5A757`). On Bitbucket, apply the equivalent
label/tag via the PR UI/API. Skip silently if no label was requested.

### Step 8 — Link PR back to Jira

```
mcp__mcp-atlassian__jira_add_comment(
  issue_key=<jira-key>,
  comment="PR opened: <pr-url>"
)
```

### Step 9 — Report

Output:
- **Branch**: `<branch-name>`
- **Target**: `<target-branch>`
- **Title**: `<pr-title>`
- **Risk**: Low / Medium / High
- **PR URL**: `<url>`
- **Reviewers needed**: 2 approvals (must include Tech Lead) for master; 1 for hotfix
- **CI gates**: Build, Unit tests ≥70%, Lint, SonarQube — all must pass before merge

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

- **Branch not pushed yet**: push first with `-u`
- **PR already exists for branch**: fetch existing PR, offer to update description
- **MCP Bitbucket/GitHub unavailable**: fall back to `gh` CLI (GitHub) or output the PR body and ask user to create manually
- **Jira ticket closed**: warn — should this PR exist?
- **Target branch is develop/staging**: refuse — per §15, PR to master only. Direct merge to develop doesn't need PR.

---

## Hard refusals

- Do NOT open PR targeting `develop` or `staging` (no PR required per §15; direct merge only)
- Do NOT open PR from `master` / `develop` / `staging` / `release/*` as source
- Do NOT bypass the rebase check — per §15 "zero conflicts required"
- Do NOT fabricate test evidence — flag as pending if missing
- Do NOT add an AI-assistant attribution line to the PR body (`Co-Authored-By: Claude...`, `🤖 Generated with...`) — forbidden by §13

---

## What this skill does NOT do

- Does not auto-rebase (user must rebase manually to handle conflicts)
- Does not run CI locally (CI runs on the remote after push)
- Does not approve or merge (that's reviewer + Tech Lead)
- Does not handle hotfix-specific flow (use `/omh-hotfix` — different branch source and 1-approval rule)

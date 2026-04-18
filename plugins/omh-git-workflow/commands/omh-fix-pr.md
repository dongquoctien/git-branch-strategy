# Fix PR Blockers (OMH Git Strategy §13, §15)

**Usage**: `/omh-fix-pr [pr-number-or-url]`

Examples:
- `/omh-fix-pr` — fix blockers on current branch's PR
- `/omh-fix-pr 42` — fix a specific PR by number

Parse arguments from: $ARGUMENTS
- Optional: PR number or URL

---

## Relationship to `/omh-check-pr`

- `/omh-check-pr` = **audit** (read-only scorecard of §13 + §15 compliance)
- `/omh-fix-pr` = **action** (walk through each blocker and offer concrete fix)

This skill calls `/omh-check-pr` logic internally, then for each failing gate asks the user whether to fix it and runs the corresponding action.

---

## Rules (from README §13 Required PR Fields + §15 PR Policy)

All 8 required fields per §13:
1. Title (conventional commit format) — `<type>(scope): description`
2. Summary (2–5 sentences, what + why)
3. Changed files / components list
4. Test evidence
5. Risk level (Low / Medium / High)
6. Jira ticket(s) linked
7. Rebase confirmation (zero conflicts per §15)
8. Rollback plan (only when risk = High)
9. Migration notes (only for DB/infra changes)

CI gates per §15 CI Enforcement — Build, Unit tests ≥70%, Lint, SonarQube, AI review.

Approvals per §15 — 2 for work branch (incl. Tech Lead), 1 for hotfix.

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended. Bundle independent questions (max 4).

---

## Workflow

### Step 1 — Run audit

Execute the same data collection as `/omh-check-pr` (Steps 1–5 of that skill). Build blocker list.

Each blocker is one of:
- `field_missing:<field>` — one of the 8 required fields is empty or placeholder
- `field_invalid:<field>` — e.g. subject > 50 chars, risk level missing justification
- `rebase_behind` — N commits behind master
- `ci_failing:<gate>` — Build/Tests/Lint/Sonar failed
- `ci_pending` — CI still running (not a hard blocker but user may want to wait)
- `approvals_missing` — need N more approvals
- `tech_lead_missing` — no Tech Lead among reviewers

### Step 2 — Classify and prioritize

Sort blockers by fix-time:
1. **Fast fixes** (< 1 min): missing PR body fields, missing Jira link
2. **Local actions** (1–5 min): rebase onto master
3. **External actions** (variable): fix failing CI, request Tech Lead review
4. **Wait** (indefinite): CI running, pending approvals

Show summary:
```
PR #N has <count> blockers:
  Fast fixes: <field-missing items>
  Local actions: <rebase items>
  External: <CI fails, TL missing>
  Wait: <CI pending, approvals pending>

Fix in order?
```

### Step 3 — Offer fix path

```
AskUserQuestion:
  question: "How to proceed on PR #N blockers?"
  header:   "Fix plan"
  multiSelect: false
  options:
    - "Walk through each fast fix" (Recommended) — description: "I'll prompt for each missing field in order"
    - "Fix rebase first" — description: "Rebase onto master (runs /omh-sync-master)"
    - "Show only, I'll fix manually" — description: "Print all blockers and exit"
    - "Cancel" — description: "Do nothing"
```

### Step 4A — Walk through fast fixes (PR body fields)

For each `field_missing:*` or `field_invalid:*` blocker, prompt via `AskUserQuestion`:

**Missing Summary**:
```
question: "PR Summary is empty or too short. What changed and why?"
header:   "Summary"
options:
  - "Generate from commits" (Recommended) — description: "Auto-draft from git log; I confirm before posting"
  - "Write myself" — description: "I type via Other"
  - "Skip this blocker" — description: "Leave for Tech Lead to push back on"
```

For "Generate from commits": run `git log origin/master..HEAD --format='%s%n%n%b'`, summarize (use the commit subjects + bodies), show preview, confirm, then `gh pr edit --body`.

**Missing Changed files / components**:
```
question: "List affected modules?"
header:   "Components"
options:
  - "Auto-generate from diff" (Recommended) — description: "git diff --dirstat | group by top-level dir"
  - "Write myself" — description: "Type via Other"
  - "Skip" — description: "Not recommended"
```

**Missing Test evidence**:
Same `AskUserQuestion` as `/omh-open-pr` Step 4 (Test evidence multiSelect). If all options empty, mark as "pending — requires Tech Lead sign-off".

**Missing Risk level**:
Re-run the inference logic from `/omh-open-pr` Step 4 (Risk level), confirm with user.

**Missing Rollback plan** (risk=High only):
```
question: "Describe the rollback procedure for this High-risk change:"
header:   "Rollback"
options:
  - "I type it (via Other)" — description: "Required per §13 for High risk"
  - "Downgrade risk to Medium" — description: "Only if the change is actually Medium"
  - "Cancel" — description: "High-risk PRs cannot proceed without rollback plan"
```

**Missing Migration notes** (DB/infra touched):
Prompt user for: estimated run time, zero-downtime (yes/no), rollback SQL/procedure.

**Missing Jira link**:
```
question: "What Jira ticket does this PR reference?"
header:   "Jira"
options:
  - "Use branch-derived key: <key>" (Recommended) — description: "Extract from branch name pattern"
  - "Type different key (via Other)" — description: "Branch name may have been wrong"
  - "No Jira — skip" — description: "⚠️ §11 requires every PR linked to a Jira ticket"
```

**Subject > 50 chars**:
```
question: "PR title is <N>/50 chars. Shorten?"
header:   "Title"
options:
  - "Generate shorter variant" (Recommended) — description: "Auto-shorten preserving type/scope"
  - "Write myself" — description: "Type via Other"
  - "Keep (won't pass audit)" — description: "Skip this blocker"
```

### Step 4B — Rebase if behind master

If blocker `rebase_behind` exists:
```
question: "Branch is N commits behind master. Rebase now?"
header:   "Rebase"
options:
  - "Rebase (run /omh-sync-master)" (Recommended) — description: "May produce conflicts requiring manual resolution"
  - "Skip — I'll rebase manually" — description: "Do NOT request review until rebased"
```

If accepted, invoke the `/omh-sync-master` flow programmatically. If conflicts → stop, surface conflicts, let user resolve and re-run `/omh-fix-pr`.

### Step 4C — External actions

For `ci_failing:<gate>`:
```
question: "CI <gate> is failing. Next step?"
header:   "CI fail"
options:
  - "Run /omh-ci-status for details" (Recommended) — description: "See specific failure log"
  - "Re-run CI" — description: "gh run rerun / Bitbucket equivalent"
  - "Skip — I'll investigate locally" — description: "Close skill"
```

For `tech_lead_missing`:
```
question: "No Tech Lead among reviewers. Request one?"
header:   "TL missing"
options:
  - "Request Tech Lead" (Recommended) — description: "Run /omh-reviewers to add TL"
  - "I'll assign manually" — description: "Close skill"
  - "Skip" — description: "PR cannot merge per §15"
```

For `approvals_missing` (count > 0 but not enough):
```
question: "Need N more approvals. Nudge reviewers?"
header:   "Approvals"
options:
  - "Ping in team channel" — description: "Print suggested message + PR URL"
  - "Request re-review" — description: "gh pr ready / re-request on GitHub"
  - "Skip — just waiting" — description: "Close skill"
```

### Step 4D — Wait cases

For `ci_pending` or `approvals_pending`:
```
question: "CI/approvals still pending. Watch until done?"
header:   "Watch"
options:
  - "I'll check back manually" (Recommended) — description: "Exit skill"
  - "Print /loop command" — description: "Show /loop /omh-ci-status command to poll"
```

Skill itself does NOT loop — suggests the user invoke `/loop` if they want polling.

### Step 5 — Apply fixes sequentially

After gathering all answers, apply in order:
1. PR body updates → one `gh pr edit --body "..."` call (batched)
2. Rebase → `/omh-sync-master` flow (conflicts stop everything)
3. Reviewer requests → `/omh-reviewers` flow
4. External action prompts → print instructions, don't execute

After each apply, re-run `/omh-check-pr` audit silently to confirm the blocker cleared.

### Step 6 — Final verification

Re-audit PR. If all §13 required fields filled + rebase clean + Tech Lead present + CI green → print:

```
✅ PR #N is ready to merge

Next (for Tech Lead):
  /omh-check-pr N   — final audit
  gh pr merge N --squash --delete-branch
```

If blockers remain (some external, some pending), print clear list of what's left:

```
⏳ PR #N still has N blockers:
  <each remaining blocker with action required>
```

---

## Hard refusals

- Do NOT fabricate test evidence — always flag as pending if user can't provide
- Do NOT lower risk level to bypass rollback plan requirement — §13 requires it for High
- Do NOT auto-merge — Tech Lead must be final approver per §15
- Do NOT re-run CI in a loop — the skill offers trigger once, user decides polling
- Do NOT edit PR body of someone else's PR without confirmation

---

## What this skill does NOT do

- Does not audit from scratch (uses `/omh-check-pr` output)
- Does not merge the PR (Tech Lead does via GitHub UI or `gh pr merge`)
- Does not rebase without user confirmation (delegates to `/omh-sync-master`)
- Does not request Tech Lead reviewers directly (delegates to `/omh-reviewers`)

# Hotfix Flow (OMH Git Strategy §10, §15)

**Usage**: `/omh-hotfix <JIRA-KEY> [short-description] [phase]`

Examples:
- `/omh-hotfix OMH-4857 fix-code-generator` — start from phase 1 (branch creation)
- `/omh-hotfix OMH-4857 fix-code-generator 4` — jump to phase 4 (emergency release branch) if earlier phases done

Parse arguments from: $ARGUMENTS
- First: Jira key (required, `^[A-Z]+-[0-9]+$`)
- Second: kebab-case description
- Third (optional): phase number 1–7 to resume from

---

## Rules (from README §10 Hotfix Flow + §15 Tech Lead Policy + §11 Naming)

- Hotfix branch pattern: `hotfix/{JIRA-KEY}-{description}` — **only branch type with prefix** (§11)
- **Always create hotfix branch from latest production TAG** — not from master, not from any release branch (§10)
- Upstream-first: fix merges to **master first**, then flows through emergency release branch
- **hotfix/* branches never deploy directly** — staging/production deploys happen through a `release/*` branch
- Active release branch handling: if staging is occupied by an active release, **cherry-pick** the merge commit SHA — never `git merge hotfix/...` (would pull unrelated history)
- Tech Lead required for: PR approval (1 approval — hotfix rule §15), release branch creation, staging reset, tag push
- develop is NOT directly updated — periodic reset picks up the hotfix on next cycle
- Patch version bump (e.g. v1.2.0 → v1.2.1) per §23

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended. Bundle independent questions (max 4).

---

## The 7 Phases

This skill walks through §10 step by step. Each phase is gated by `AskUserQuestion`. User can abort any phase; resume with `/omh-hotfix <key> <desc> <phase>`.

### Phase 1 — Branch creation from production tag

Preflight:
```bash
git fetch origin --tags --prune
git tag --sort=-version:refname | head -5
git status --porcelain
```

Confirm Tech Lead / emergency:
```
AskUserQuestion:
  question: "Hotfix requires Tech Lead awareness per §15. Confirm role + urgency."
  header:   "Auth"
  options:
    - "Tech Lead, urgent production fix" (Recommended) — description: "Proceed full flow"
    - "Dev with Tech Lead approval" — description: "Proceed; Tech Lead will approve PR in phase 3"
    - "Not urgent — use /omh-new-branch instead" — description: "Cancel; follow normal flow"
```

If description missing, fetch Jira ticket (`mcp__mcp-atlassian__jira_get_issue`) and offer 3 candidates via `AskUserQuestion` (same pattern as `/omh-new-branch`).

Pick production tag to branch from:
```
AskUserQuestion:
  question: "Which production tag to branch the hotfix from?"
  header:   "From tag"
  options:
    - "<latest tag>" (Recommended) — description: "Most recent production release"
    - "<second latest>" — description: "Older version — rare case"
    - "<third latest>" — description: "Only if specific reason"
```

Execute:
```bash
git checkout -b hotfix/{JIRA-KEY}-{description} <tag>
```

Refuse to create from master or release branches (§10 hard rule).

### Phase 2 — Development

This skill pauses here. User implements the fix with **targeted changes only** (no refactoring per §10).

Print guidance:
> Implement the minimal fix. Commit narrowly — the merge commit SHA will be cherry-picked into active release branches later. Then:
> - Stage changes
> - Run `/omh-commit` (use `fix` type, NOT `hotfix` — per §14 note)
> - Push: `git push origin hotfix/{JIRA-KEY}-{description}`
> Re-run `/omh-hotfix {JIRA-KEY} {description} 3` when commit(s) are ready.

### Phase 3 — PR to master (upstream first)

Preflight: branch pushed, rebased onto master, CI passing.

Use `/omh-open-pr` flow but override two rules for hotfix:
- Target: `master`
- Approvals: 1 (Tech Lead required per §15)
- Title: `hotfix(<scope>): <subject>` — scope from §14 list
- Risk level: always **High** (production fix by definition) — auto-fill rollback plan prompt

This skill calls `/omh-open-pr` flow programmatically. After merge to master, capture the **merge commit SHA** (needed for phase 5):
```bash
git fetch origin master
git log origin/master -1 --format=%H   # merge commit SHA
```

Store this SHA — it's used for cherry-pick in phase 5 (never use the hotfix branch SHAs directly).

### Phase 4 — Emergency release branch

Create release branch from master (master now contains the hotfix merge):
```bash
git fetch origin master
git checkout -b release/v{X}.{Y}.{Z+1}-{description} origin/master
git push origin release/v{X}.{Y}.{Z+1}-{description}
```

Version bump: **patch** (e.g. v1.2.0 → v1.2.1 per §23).

Prompt to confirm patch version:
```
AskUserQuestion:
  question: "Patch version for emergency release? (current prod tag: <latest>)"
  header:   "Version"
  options:
    - "v{X}.{Y}.{Z+1}" (Recommended) — description: "Standard patch bump per §23"
    - "v{X}.{Y}.{Z+2}" — description: "Previous patch already deployed; skip number"
```

### Phase 5 — Handle active release branch

Check if any other `release/*` branch exists (one that predates this hotfix):
```bash
git branch -r | grep 'origin/release/' | grep -v 'v{X}.{Y}.{Z+1}' | sed 's|.*origin/||'
```

If none → skip phase 5, go to phase 6.

If one or more → ask:
```
AskUserQuestion:
  question: "Active release branch detected. Cherry-pick the hotfix into it? (§10 step 5)"
  header:   "Active rel"
  options:
    - "Cherry-pick into active release" (Recommended) — description: "Preserves release candidate cleanness"
    - "Skip — active release will be rebuilt from master later" — description: "Only if that release is about to be scrapped"
```

If cherry-pick:
```bash
git checkout <active-release-branch>
git cherry-pick <merge-commit-sha-from-phase-3>
git push origin <active-release-branch>
```

**Never** `git merge hotfix/...` into release — §10 hard rule.

### Phase 6 — Testing on staging

Tech Lead decides which branch staging follows based on occupancy. Ask:
```
AskUserQuestion:
  question: "Which branch should staging deploy?"
  header:   "Staging"
  options:
    - "Emergency release branch (vX.Y.Z+1-*)" (Recommended) — description: "Standard hotfix flow"
    - "Active release branch (with cherry-pick)" — description: "If active release is next to deploy"
    - "Skip staging (emergency, tag immediately)" — description: "⚠️ Bypasses QA gate — Tech Lead approval required"
```

Execute staging reset via `/omh-reset-staging release <chosen-branch>` flow.

Pause for QA targeted regression test.

### Phase 7 — Deployment

Preflight re-checks:
- Current branch = emergency release branch
- Tag does not exist yet
- QA sign-off

```
AskUserQuestion:
  question: "QA signed off? Tagging triggers emergency production deploy."
  header:   "QA sign"
  options:
    - "Yes, tag and deploy" (Recommended) — description: "Tech Lead confirms sign-off"
    - "QA found new issue" — description: "Stop; apply another /omh-cherry-pick upstream-first"
    - "Cancel" — description: "Don't deploy"
```

Execute:
```bash
git checkout release/v{X}.{Y}.{Z+1}-{description}
git tag -a v{X}.{Y}.{Z+1} -m "Hotfix v{X}.{Y}.{Z+1}: {description}"
git push origin v{X}.{Y}.{Z+1}
```

After 30-min validation window (§19), cleanup:
```
AskUserQuestion:
  question: "Deployment validated? Clean up branches?"
  header:   "Cleanup"
  options:
    - "Delete hotfix + release branches" (Recommended) — description: "Per §12: hotfix immediately, release within 1 day"
    - "Keep for rollback reference" — description: "Delete later"
    - "Initiate rollback" — description: "Run /omh-rollback"
```

Delete:
```bash
git push origin --delete release/v{X}.{Y}.{Z+1}-{description}
git push origin --delete hotfix/{JIRA-KEY}-{description}
git branch -d release/v{X}.{Y}.{Z+1}-{description} 2>/dev/null
git branch -d hotfix/{JIRA-KEY}-{description} 2>/dev/null
```

### Final report

- **Hotfix**: `{JIRA-KEY}` — {description}
- **From tag**: `<original-prod-tag>`
- **Merge to master**: `<merge-commit-sha>`
- **Emergency release**: `v{X}.{Y}.{Z+1}` — tagged + deployed
- **Active release cherry-pick**: applied / n/a
- **Branches**: deleted / kept
- **develop sync**: deferred — picked up on next `/omh-reset-develop` cycle per §10

---

## Hard refusals

- Do NOT create hotfix branch from master or release/* — only from a production tag
- Do NOT deploy from hotfix/* directly — always via emergency release branch
- Do NOT `git merge hotfix/...` into active release — cherry-pick merge SHA only
- Do NOT skip PR to master — upstream-first is mandatory (§10 step 3)
- Do NOT skip CI on hotfix PR (§15 — hotfix CI gate is non-bypassable)
- Do NOT use `hotfix` as commit type — use `fix` (§14 note)

---

## What this skill does NOT do

- Does not fix the underlying bug (user implements in phase 2)
- Does not push back-merge to develop (periodic `/omh-reset-develop` handles this)
- Does not notify incident channel (user does per §21)
- Does not write the post-mortem (per §21, open Jira ticket within 24h)

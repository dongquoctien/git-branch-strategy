# Rollback Procedure (OMH Git Strategy §20, §21, §15)

**Usage**: `/omh-rollback [target-tag]`

Examples:
- `/omh-rollback` — full interactive flow
- `/omh-rollback v1.2.0` — roll back to a specific prior tag

Parse arguments from: $ARGUMENTS
- Optional: previous stable tag to roll back to (default: auto-detect previous tag)

---

## Rules (from README §20 Rollback Trigger + §21 Rollback Procedure + §15 Tech Lead Policy)

- **Only Tech Lead or Manager may initiate a rollback** (§15)
- Rollback is triggered by §20 conditions within 30 minutes of deployment:
  - Error rate spike > 5% above baseline
  - Critical path failure (search, booking, login, payment)
  - DB migration failure or data integrity issue
  - Critical alert fired
- **Preferred path**: re-trigger previous tag via CI/CD pipeline (fastest, safest — no git changes)
- **Fallback**: revert merge commit on master + push new patch tag (when pipeline unavailable)
- After rollback: new patch tag required (e.g. v1.2.2 after rolling back v1.2.1)
- Responsible party: on-call engineer executes; Tech Lead + Manager notified immediately
- Post-mortem Jira ticket within 24 hours

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended. Bundle independent questions (max 4).

---

## Workflow

### Step 1 — Authorization

```
AskUserQuestion:
  question: "Rollback requires Tech Lead or Manager per §15. Who are you?"
  header:   "Role"
  options:
    - "Tech Lead" (Recommended) — description: "Authorized to initiate rollback"
    - "Manager" — description: "Authorized per §21"
    - "On-call engineer (TL/Mgr notified)" — description: "Authorized to execute; confirm notification"
    - "Neither — cancel" — description: "Escalate immediately"
```

Stop if not authorized.

### Step 2 — Capture trigger reason

```
AskUserQuestion:
  question: "Which §20 trigger prompted the rollback?"
  header:   "Trigger"
  multiSelect: true
  options:
    - "Error rate >5% above baseline" — description: "Visible in monitoring within 30 min of deploy"
    - "Critical path failure" — description: "search / booking / login / payment broken"
    - "DB migration or data integrity issue" — description: "§20"
    - "Critical alert fired" — description: "Monitoring system paged"
```

Record the selected triggers — they go into the post-mortem.

### Step 3 — Identify current and target versions

Run in parallel:
```bash
git fetch origin --tags --prune
git tag --sort=-version:refname | head -10
git log origin/master -10 --oneline --merges
```

Current tag = highest version tag at or before current production HEAD. Previous stable = second-highest (skip any prior hotfix-revert-hotfix cycle tags).

If `$ARGUMENTS` specifies a target tag, validate it exists.

Otherwise ask:
```
AskUserQuestion:
  question: "Which tag to roll back TO? (current prod: <current-tag>)"
  header:   "Target"
  options:
    - "<previous-tag>" (Recommended) — description: "Most recent stable tag before <current>"
    - "<tag-before-that>" — description: "Two releases back — only if previous is also suspect"
    - "<third-back>" — description: "Rarely correct — prefer fix-forward"
```

### Step 4 — Pick rollback method

Check CI/CD pipeline availability. Ask:
```
AskUserQuestion:
  question: "CI/CD pipeline available to re-trigger <target-tag>?"
  header:   "Method"
  options:
    - "Yes — re-trigger pipeline" (Recommended) — description: "§21 preferred: fastest, safest, no git changes"
    - "No — revert merge commit + re-tag" — description: "§21 fallback: git revert + new patch tag"
    - "Unknown — check pipeline first" — description: "Cancel; verify pipeline then re-run"
```

### Step 5A — Preferred: pipeline re-trigger

Print pipeline trigger instructions (skill does not auto-trigger external CI — user does this in CI UI or via their own `gh workflow run` / Bitbucket API):

```
Method: Re-trigger previous tag via CI/CD

Action required from user:
  - Navigate to CI/CD pipeline UI
  - Trigger deployment for tag <target-tag>
  - Monitor deploy logs
  - Verify health check + error rate after deploy
```

Ask via `AskUserQuestion` whether user wants a suggested CI trigger command (GitHub Actions / Bitbucket Pipelines / Jenkins) — do NOT auto-invoke.

### Step 5B — Fallback: revert + re-tag

Preflight:
- User on latest `master` with clean tree
- Identify the merge commit to revert

Run:
```bash
git checkout master
git pull origin master
git log -10 --merges --format='%h %s'
```

Ask which merge commit to revert:
```
AskUserQuestion:
  question: "Which merge commit to revert on master?"
  header:   "Revert"
  options:
    - "<sha-1> <subject>" (Recommended) — description: "Most recent merge (usually the cause)"
    - "<sha-2> <subject>" — description: "Previous merge"
    - "<sha-3> <subject>" — description: "Older merge — rare"
```

Preview the revert:
```bash
git revert <sha> --no-edit -n   # dry run staged in index
git diff --staged --stat
git revert --abort                # roll back the preview
```

Confirm:
```
AskUserQuestion:
  question: "Execute revert + push + tag v<X>.<Y>.<Z+1>?"
  header:   "Confirm"
  options:
    - "Cancel" (Recommended) — description: "Review diff first"
    - "Proceed" — description: "IRREVERSIBLE on history: reverts merge and pushes new patch tag"
```

Execute:
```bash
git revert <sha> --no-edit
git push origin master
git tag -a v{X}.{Y}.{Z+1} -m "Rollback v{X}.{Y}.{Z+1}: revert <target-tag>"
git push origin v{X}.{Y}.{Z+1}
```

### Step 6 — Notification (§21)

```
AskUserQuestion:
  question: "Incident channel + Tech Lead + Manager notified?"
  header:   "Notify"
  options:
    - "Yes, already notified" (Recommended) — description: "Proceed"
    - "Not yet — I'll post now" — description: "Print suggested incident message template"
    - "Emergency override — skip for now" — description: "⚠️ Must notify within 10 min"
```

If user picks "I'll post now", print an incident message template:
```
🚨 Production rollback initiated

Trigger: <step 2 selections>
Current tag: <current>
Target tag: <target>
Method: <pipeline re-trigger | revert+re-tag>
New tag: <v-next-patch>  (if fallback path)
Responsible: <user handle>

Post-mortem ticket: pending (§21 requires within 24h)
```

### Step 7 — Verify rollback

After deploy completes, check §19 Deployment Validation gates:
```
AskUserQuestion:
  question: "Post-rollback validation gates passing? (health check, error rate, key metrics)"
  header:   "Validate"
  options:
    - "All gates green" (Recommended) — description: "Rollback successful; move to post-mortem"
    - "Partial — monitoring" — description: "Wait 10 min, re-check"
    - "Still failing — escalate" — description: "⚠️ Rollback did not fix; escalate to Manager immediately"
```

### Step 8 — Post-mortem setup

Per §21: open post-mortem Jira ticket within 24 hours.

```
AskUserQuestion:
  question: "Open post-mortem Jira ticket now?"
  header:   "Postmortem"
  options:
    - "Open now (auto via Jira MCP)" (Recommended) — description: "Create ticket with rollback context + triggers"
    - "I'll open manually" — description: "Print suggested fields template"
    - "Defer to dedicated incident tool" — description: "Using external runbook"
```

If user picks "Open now", call `mcp__mcp-atlassian__jira_create_issue` with prefilled summary/description:
- Summary: `Post-mortem: Rollback v{current} → v{target} on YYYY-MM-DD`
- Description: includes triggers (step 2), method used (step 4), notification log, and validation outcome (step 7)
- Labels: `incident`, `post-mortem`

### Step 9 — Report

- **Rolled back**: `<current-tag>` → `<target-tag>`
- **Method**: pipeline re-trigger / revert+re-tag
- **New tag** (if fallback): `v<X>.<Y>.<Z+1>`
- **Validation**: all gates green / partial / failing
- **Notification**: sent / deferred
- **Post-mortem ticket**: <Jira-KEY> / pending manual
- **Next**: 24h post-mortem; fix-forward with `/omh-hotfix` when root cause identified

---

## Hard refusals

- Do NOT initiate rollback without Tech Lead/Manager role confirmation (§15)
- Do NOT skip incident notification except with explicit emergency override
- Do NOT use raw `git push --force` to rewrite master — use `git revert` (§21 fallback path)
- Do NOT skip creating a new patch tag after the revert — CI/CD expects tag-triggered deploys
- Do NOT roll back without capturing the §20 trigger reason (blocks post-mortem quality)

---

## What this skill does NOT do

- Does not monitor deploy metrics in real-time (user does via Grafana/monitoring)
- Does not auto-trigger CI/CD pipeline (provides instructions; user initiates in CI UI)
- Does not write the full post-mortem content (opens ticket; investigator fills it in)
- Does not re-deploy the original version (use `/omh-hotfix` to fix-forward, or `/omh-release` for the next planned cut)

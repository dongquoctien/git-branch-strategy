# VOC SQL Migration → PR to master (SOP SQL Validation §1–§6)

**Usage**: `/omh-voc-migration <JIRA-KEY> [repo-path]`

Examples:
- `/omh-voc-migration ELS-2093` — pull SQL from the ticket's comments, scaffold a migration script, open the PR
- `/omh-voc-migration ELS-2093 D:\Code\oh-api` — point at a specific local clone

Parse arguments from: $ARGUMENTS
- First token matching `^[A-Z]+-[0-9]+$` (or a Jira URL containing one) → **jira_key**
- A filesystem path or repo name → **repo_path** (default `D:\Code\oh-api`)

This skill turns a VOC / data-fix request into a **reviewed, rollback-able SQL migration script** committed under the backend's `migration/` folder and opened as a PR to `master` — the only sanctioned path to running data-mutating SQL on Production (SOP §2). It performs the **Claude AI SQL Review** (SOP §3) itself and seeds the **Production Approval Checklist** (SOP §6) into the PR. It does **not** execute SQL anywhere.

---

## Rules (from SOP SQL Validation §1–§6, + Git Strategy + SLA §6)

- **Subtask-first (company rule)**: if the ticket being VOC'd is a **parent Task** with no Subtask assigned to the **current MCP user** (resolve via `jira_get_user_profile("currentUser")` — do NOT hard-code Tom), **create one first** — Subtask, assignee = current user, status **In Progress** (Step 0). The migration work is tracked under that subtask. If the ticket is already a Subtask, skip. **Never create a duplicate if a subtask already assigned to the current user exists — reuse it** (just ensure In Progress). Also fill its **schedule fields** (Step 0.3): Start date = today; Due date + Stg release date = parent's Stg release date if set, else Medium (start + 1–2 days); Estimated duration in **days** (1 day = 8 h, so 1 h = 0.125).
- Applies to Production-mutating SQL: `UPDATE` / `DELETE` / bulk `INSERT` / `ALTER TABLE` / data-migration / VOC scripts (SOP §1)
- **Prerequisites (SOP §2)**: a Jira ticket, committed to Git, PR approved, **merged to master before any execution**, following the Git Strategy. Direct PROD execution outside the Git process is **prohibited**.
- **Step 1 — Claude AI SQL Review (SOP §3)**: review Full-Table-Scan / Missing-Index / Lock / Estimated-Impact / Recommendations, and the review block **must be attached to the PR**.
- **Step 2 — Staging execution (SOP §4)** with evidence (execution time, rows affected, screenshot, CloudWatch) — this is a **human** step; the skill only checklists it, never runs SQL.
- **Large changes (SOP §5)**: split into smaller batches, not one large transaction.
- **Production Approval Checklist (SOP §6)**: 10 items; missing any one ⇒ must not run on Production.
- **SLA §6 overlay**: if the op is ≥ 50,000 rows or est. > 120 s, it is a Heavy Data Operation — also needs CTO approval, the Regular Deployment Window (Tue & Thu 06:00–08:00 GMT+7), and real-time monitoring.
- **Branch/PR**: the work branch `{JIRA-KEY}-voc-{desc}` is **always cut from `origin/master`** — never from the current HEAD, `develop`, `staging`, or any other branch (§11). Always `git fetch origin master` first so the base is up to date. Open the PR via `/omh-open-pr` (§13/§15) — do not reimplement PR logic here.
- **Secrets**: never commit real secrets/keys (e.g. an inline `AES_DECRYPT('<key>')`) into a git-tracked script (CLAUDE.md "no secrets in plugin/repo files") — stop and require a placeholder or secret store.

---

## Interaction convention — ALWAYS use AskUserQuestion

**Do NOT print numbered options as text and wait for the user to type a number.** Every input uses the `AskUserQuestion` tool.

- `header`: ≤12 chars chip label
- `options`: 2–4 items, mutually exclusive unless `multiSelect: true`
- Do NOT add an "Other" option — the tool adds it for free-text
- First option = recommended/safest, suffix `" (Recommended)"`
- Destructive / outward-publishing options last, description starting with `"IRREVERSIBLE: "` or `"PUBLISHES: "`
- Always offer Cancel for non-trivial actions
- Bundle independent questions into ONE call (max 4)
- Every Jira write or PR creation is an outward action → preview + confirm

---

## Workflow

### Step 0 — Ensure a working Subtask exists on the VOC parent (company rule)

**Company rule:** whenever you VOC a **parent** ticket (a Task, not a Subtask), the actual work must
live in a **Subtask assigned to the current engineer (the person whose token is connected to this MCP)
with status In Progress**. This subtask is where the SQL/migration work is tracked. Do this **before**
collecting SQL so you never repeat it later. (Reference: ELS-2692 → subtask ELS-2693;
ELS-2946 → subtask ELS-2948.)

**"The engineer" = the current MCP user, resolved at runtime — do NOT hard-code an email/name.**
Get their accountId once with `jira_get_user_profile(user_identifier="currentUser")` (or
`get_me`-equivalent), and compare subtasks' assignee against **that** accountId. In this project the
current user is usually Tom (`tien.dq@ohmyhotel.com`), but the skill must stay flexible — whoever is
connected is the assignee.

1. **Detect.** From the Step-1 fetch (or a quick `jira_get_issue(jira_key, fields="issuetype,subtasks,assignee")`):
   - If `jira_key` **is itself a Subtask** (`issuetype.subtask == true`) → skip Step 0 entirely; work directly on it (transition it to In Progress if it isn't already).
   - If `jira_key` is a **parent Task** and **already has a subtask assigned to the current user** → **reuse it, do NOT create another**; just ensure it is In Progress. (Match on the resolved accountId — a subtask assigned to someone else does NOT count.)
   - If `jira_key` is a **parent Task with no subtask assigned to the current user** → create one (next).

2. **Create the working subtask** (mirror the ELS-2693 style — action-oriented summary
   "Verify data and logic to <the change requested> for <hotel/booking>"):
   ```
   jira_create_issue(
     project_key = "ELS",              # same project as the parent
     issue_type  = "Subtask",          # capital S, one word — NOT "Sub-task"
     summary     = "Verify data and logic to <change> for <hotel/booking scope>",
     description = "<one-paragraph scope: what to change, the booking/hotel list, guard notes>",
     assignee    = "<current user's email / accountId>",   # resolved above, not hard-coded
     additional_fields = {"parent": "<parent JIRA-KEY>"}
   )
   ```
   A subtask is created in the default status (usually **To Do**), so **transition it to In Progress**:
   `jira_get_transitions(<subtask key>)` → find the `In Progress` transition id (typically **21** on
   the ELS board) → `jira_transition_issue(<subtask key>, transition_id)`.

3. **Fill the schedule fields (company rule)** — set these on the subtask via
   `jira_update_issue(<subtask key>, fields={...})`. **ELS field IDs** (resolve once with
   `jira_get_create_fields(project_key="ELS", issue_type_id=<Subtask id, 10013>)` if unsure — they are
   project-scoped, do NOT reuse another project's `customfield_*`):
   - **Start date** = `customfield_10015` → **today** (the day work starts). Get "today" from context
     (the session's current-date reminder) — script globals have no clock.
   - **Due date** = `duedate` (system) **AND** **Stg release date** = `customfield_10178` → set BOTH to
     the **same value**: the staging release date. **Priority order:**
       1. If the **parent Task has a Stg release date** (`customfield_10178`) → use the parent's value.
       2. Else → default **Medium: start + 1–2 working days** (a typical VOC data-fix is ~1 day, so
          start + 1 is the usual pick; use +2 for a larger multi-part change).
   - **Estimated duration** = `customfield_10179` → **in DAYS**, where **1 working day = 8 h**
     (so 1 h = **0.125**, 2 h = **0.25**, 4 h = 0.5, a full day = 1). Estimate the *actual effort* of the
     fix (not the due-date window): a single-column/method flip or allotment revert ≈ 1–2 h (**0.125–0.25**);
     a multi-statement / multi-room migration ≈ 0.5. Confirm the number via AskUserQuestion when unsure.
   Example (payment-method flip, parent has no Stg date, started 2026-08-04):
   `fields = {"customfield_10015":"2026-08-04", "duedate":"2026-08-05",
              "customfield_10178":"2026-08-05", "customfield_10179":0.25}`.
   When **reusing** an existing subtask (Step 1 branch 2), still backfill any of these that are empty.

4. **Confirm before creating** (outward write) via AskUserQuestion — preview the subtask summary +
   parent + assignee + the schedule fields. Skip the prompt only if the user explicitly asked to
   auto-create it.

5. **From here on, the migration work (branch name, commit, PR) still references the PARENT
   `jira_key`** for the `VOC(<parent>):` title and folder — the subtask is the Jira-side work tracker,
   not the branch key. (Optionally note the subtask key in the PR body / report.)

> Note: the **Reporter** on a freshly-created ELS subtask cannot be set via the API (screen
> restriction — same as `[[jira-clone-btbs-els]]`); it defaults to the creating (current) user, which
> is fine here since that same user is the assignee doing the work.

### Step 1 — Load the ticket & collect SQL

Read the ticket: `mcp__mcp-atlassian__jira_get_issue(issue_key=jira_key, fields="*all", comment_limit=50)`. Extract summary, description, attachments, and **every fenced ```` ```sql ```` block across all comments** (a ticket may carry several — e.g. "Tháng 4" / "Tháng 5" as separate comments, like ELS-2093).

Present what was found and how to split it:

```
AskUserQuestion:
  question: "Found <N> SQL block(s) in <jira_key>. How to scaffold?"
  header:   "SQL blocks"
  multiSelect: false
  options:
    - "One file per block" (Recommended) — description: "e.g. 01_thang-4.sql, 02_thang-5.sql — runs in order"
    - "Single combined file" — description: "All blocks concatenated in order into one .sql"
    - "Let me pick which blocks" — description: "Multi-select the blocks to include"
    - "Cancel" — description: "Stop"
```

If **no** SQL block is found:

```
AskUserQuestion:
  question: "No SQL in the ticket. Where should the SQL come from?"
  header:   "SQL source"
  options:
    - "Generate from VOC description" (Recommended) — description: "Use ohmyhotel MCP (generate_voc_sql / generate_sql) from the ticket's VOC intent, then you review it"
    - "I'll paste the SQL" — description: "Provide the SQL via Other / follow-up"
    - "Cancel" — description: "Stop"
```

For generation, call the ohmyhotel MCP (`generate_voc_sql`, else `generate_sql`) and show the result for confirmation before continuing. Never run it; never invent table/column names — generate only from the MCP/schema.

### Step 2 — Claude AI SQL Review (SOP §3) — performed by this skill

Analyze the collected SQL and produce the review block in the SOP format. Cover every scope item:

- **Full Table Scan Risk** — any `UPDATE`/`DELETE` with no `WHERE`, or a `WHERE` that isn't sargable / hits no index.
- **Missing Index Risk** — predicate columns vs. likely indexes; flag large `IN (...)` lists, `JOIN`s on unindexed columns.
- **Lock Risk** — wide `UPDATE`/`DELETE`, multi-statement writes in sequence, `ON DUPLICATE KEY`, temp-table churn.
- **Estimated Impact** — best-effort rows affected (e.g. count of IDs in an `IN (...)` list) and rough duration class.
- **Recommendations** — batching, adding `WHERE`/`LIMIT`, index hints, separating verification `SELECT`s.

Also raise blockers explicitly:
- ⚠️ **Inline secret** — a literal key/password in the SQL (e.g. `AES_DECRYPT(UNHEX(...),'<key>')`). This is a hard stop for committing: ask to replace with a placeholder / secret reference before writing the file (Hard refusal below).
- ⚠️ **Verification `SELECT *` interleaved** — recommend moving to a separate `_verify.sql` so the apply script only mutates.
- ⚠️ **Non-idempotent** — note it in the header so re-runs are understood.

Render the block exactly in SOP §3 shape (to be attached to the PR):

```
Claude AI SQL Review (SOP §3)
Risk Level: Low / Medium / High
Summary:
- Index used: <Yes/No/Partial>
- Full Scan: <Yes/No>
- Lock Risk: <Low/Medium/High>
- Estimated rows affected: <n or range>
- Recommendation: <Safe to execute | Execute in batches | Fix before execution>
Notes: <blockers / caveats, incl. secret / idempotency findings>
```

### Step 3 — Large-change & Heavy-Op classification

From the impact estimate:
- If the op looks **large** (SOP §5) → recommend splitting into **smaller batches**; offer to scaffold per-batch files.
- If **≥ 50,000 rows or est. > 120 s** → flag **Heavy Data Operation (SLA §6)**: the PR/checklist must additionally call out CTO approval, the Regular Deployment Window (Tue & Thu 06:00–08:00 GMT+7), and real-time monitoring. Surface this; do not silently drop it.

### Step 4 — Locate the migration folder & scaffold the script(s)

Resolve `repo_path` (default `D:\Code\oh-api`) and verify the migration dir exists:
`<repo_path>\web-api\src\main\resources\migration`. If it doesn't exist → stop and report the expected path (do not create the whole tree blindly).

Create a dated folder matching the existing convention (e.g. `20260602-hotel-count-region-code`):
`migration/YYYYMMDD-<JIRA-KEY>-<short-desc>/` (confirm the folder name via AskUserQuestion if ambiguous).

Write each script with a standard header + explicit APPLY / ROLLBACK sections:

```sql
-- <JIRA-KEY>: <short description>
-- Source: VOC ticket <JIRA-KEY> (comment "<label>")
-- Date: <YYYY-MM-DD>   Author: <you>
-- Idempotent: <Yes/No>   Run order: <NN of MM>
-- SLA §6 Heavy-Op: <Yes/No>   Claude AI Review: attached in PR
-- ===== APPLY =====
<the user's SQL, unchanged in intent; secrets replaced with placeholders>

-- ===== ROLLBACK =====
-- <reverse statements, OR>
-- NOT REVERSIBLE: <reason> — recovery plan: <restore from backup taken pre-run / etc.>
```

Move any verification `SELECT` statements into a sibling `NN_<desc>_verify.sql` so the APPLY file only mutates.

> The skill writes files into the **oh-api** repo (not this plugin repo). Make that clear in the report.

### Step 5 — Branch & open the PR (delegate)

In `repo_path`:
- **Always `git fetch origin master` first**, then create the work branch **from `origin/master`** (never current HEAD / develop / staging): `git checkout -b {JIRA-KEY}-voc-{desc} origin/master` (§11) — same semantics as `/omh-new-branch`. If the working tree is dirty, stop and surface it (no silent stash).
- Stage the new migration file(s).
- **Delegate PR creation to `/omh-open-pr`** (§13/§15). Inject into the PR body:
  - The **Claude AI SQL Review block** from Step 2 (SOP §3 requires it attached).
  - The **Production Approval Checklist** (SOP §6, all 10 items as unchecked boxes).
  - The Heavy-Op note (SLA §6) if flagged.
- **VOC PR format (override the default conventional-commit title):**
  - **Title** starts with `VOC(<JIRA-KEY>):` — NOT `migration(...)` / `fix(...)` / `feat(...)`.
    e.g. `VOC(ELS-2800): Prepay/VCC -> Prepay/Cash + issue vendor billing (Pandanus Resort)`.
    (The commit message and the `migration/` folder name still use `migration(...)` — only the PR
    title changes.)
  - **Add the GitHub label `VOC`** to the PR right after it opens: `gh pr edit <n> --add-label VOC`
    (label exists on `ohmyhotelco/oh-api`, color `F5A757`). On Bitbucket, apply the equivalent
    `VOC` label/tag. This is a **repo PR label**, not a Jira label.
  - Pass the `VOC(<JIRA-KEY>): …` title into `/omh-open-pr` so it does not re-derive a
    conventional-commit title, and confirm the label was applied in the Step 6 report.

Confirm before opening:

```
AskUserQuestion:
  question: "Open PR to master for <JIRA-KEY> migration script?"
  header:   "Open PR"
  options:
    - "Open PR via /omh-open-pr" (Recommended) — description: "PUBLISHES: pushes branch + opens PR with SOP review block + §6 checklist"
    - "Just commit locally" — description: "Commit the script(s); I'll open the PR myself"
    - "Cancel" — description: "Stop"
```

### Step 6 — Report

Print:
- **Ticket**: `<jira_key>` — `<summary>`
- **Working subtask**: `<subtask key>` (assignee Tom, In Progress) — created this run, or reused if it already existed; "n/a" if the ticket was itself a subtask
- **Files**: each `migration/<folder>/<file>.sql` (+ any `_verify.sql`) written into `<repo_path>`
- **Claude AI Review**: Risk Level + one-line summary (full block in PR)
- **Heavy-Op (SLA §6)**: Yes/No
- **PR**: link (if opened) or "committed only"
- **Production Approval Checklist (SOP §6)** — print all 10 items with current state. The skill can mark **#1 Jira / #2 committed / #5 Claude AI review** as done; the rest (#3 PR approved, #4 merged, #6–#10 **Staging execution + evidence**) are **human steps**.
- **Reminder**: per SOP §2, the script **must be merged to master before any Production run**, and per SOP §6, **missing any checklist item ⇒ do not execute on Production**. Staging execution + CloudWatch evidence are done by the engineer, not this skill.

---

## Hard refusals

- Do NOT execute SQL on Production or Staging — this skill scaffolds and PRs only; running SQL + capturing evidence is a human step (SOP §4)
- Do NOT open the PR without the Claude AI SQL Review block attached (SOP §3)
- Do NOT write a migration file that contains a real secret/key (e.g. inline `AES_DECRYPT('<key>')`) — require a placeholder / secret store first
- Do NOT silently rewrite the user's SQL logic — only relocate verification `SELECT`s and replace secrets, both with the user's confirmation
- Do NOT drop the Heavy-Op (SLA §6) classification when thresholds are exceeded
- Do NOT mark the script "ready for Production" while any SOP §6 checklist item is incomplete
- Do NOT bypass the Git process (commit → PR → approve → merge) — direct PROD execution is prohibited (SOP §2)
- Do NOT cut the work branch from anything other than `origin/master` (never current HEAD / develop / staging); always fetch first (§11)

---

## What this skill does NOT do

- Does not run SQL or take CloudWatch screenshots (SOP §4 Staging evidence is the engineer's)
- Does not approve or merge the PR (review/merge per §15)
- Does not reimplement PR creation (delegates to `/omh-open-pr`)
- Does not create the incident/PIR for a failed migration (use the SLA plugin: `/omh-incident-triage`, `/omh-create-pir`)

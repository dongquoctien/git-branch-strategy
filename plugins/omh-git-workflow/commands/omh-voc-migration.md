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

- **Work on the ticket you were given (company rule, updated 2026-08-28)**: VOC work is **no longer** split into a separate Subtask — do **NOT** create one. Whatever key is passed is the working ticket, parent-level (Task, **VOC**, Bug, Story, Hotfix) or an older Subtask. On it, **backfill only the empty** schedule fields (Step 0): Start date = today; Due date + Stg release date = parent's Stg release date if there is a parent with one, else Medium (start + 1–2 days); Estimated duration in **days** (1 day = 8 h, so 1 h = 0.125). Never overwrite a value that is already set. Then move the chain to **In Progress** — the working ticket (ELS transition **21**), the parent if the ticket is an older Subtask, and the original BTBS if cloned (transition **2**); skip any already started.
- **Read the linked BTBS source ticket (Step 1)**: an ELS VOC is usually a summary and often has **no attachments** — the room/promotion/booking code spreadsheets and the requester's original wording live on the **BTBS** issue, linked via **`Blocks`** (outward `blocks`) or **`Cloners`** (outward `clones`). Never write SQL against codes from a file you have not opened.
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

### Step 0 — Prepare the ticket (schedule fields + status)

**Company rule (updated 2026-08-28): work directly on the ticket you were given.** VOC work is
**no longer** split into a separate Subtask — do **NOT** create one. Whatever key the user passes
(`jira_key`) is the working ticket: a parent-level issue (Task, **VOC**, Bug, Story, Hotfix …) or an
older Subtask created back when the subtask rule applied. Either way, work on it directly.

> **Do Step 0 up front, and don't let a flaky MCP skip it.** If `mcp-atlassian` drops mid-run,
> pause the Jira-side work and resume it once reconnected — do NOT proceed to write SQL / open the
> PR and silently leave the ticket unprepared.

1. **Fetch the ticket** — `jira_get_issue(jira_key, fields="issuetype,summary,assignee,duedate,customfield_10015,customfield_10178,customfield_10179,status")`.
   No branching on `issuetype.subtask` any more: the key you were given is the one you work on.

2. **Backfill the schedule fields — ONLY the ones that are still empty.** Never overwrite a value
   the ticket already has; the operator may have set it deliberately. Write with
   `jira_update_issue(jira_key, fields={...})`, including **only** the empty ones. **ELS field IDs**
   (project-scoped — resolve with `jira_get_create_fields(project_key="ELS", issue_type_id=<id>)` if
   unsure, do NOT reuse another project's `customfield_*`):
   - **Start date** = `customfield_10015` → **today** (the day work starts). Take "today" from the
     session's current-date reminder — script globals have no clock.
   - **Due date** = `duedate` (system) **AND** **Stg release date** = `customfield_10178` → same
     value, the staging release date. **Priority:** (1) if this ticket has a parent and that parent
     has a Stg release date, use it; (2) else default **Medium: start + 1–2 working days** (a typical
     VOC data-fix is ~1 day, so start + 1; use +2 for a larger multi-part change).
   - **Estimated duration** = `customfield_10179` → **in DAYS**, where **1 working day = 8 h**
     (1 h = **0.125**, 2 h = **0.25**, 4 h = 0.5, a full day = 1). Estimate the *actual effort*, not
     the due-date window: a single-column/method flip or allotment revert ≈ 1–2 h
     (**0.125–0.25**); a multi-statement / multi-room migration ≈ 0.5. Confirm via AskUserQuestion
     when unsure.

   Example (payment-method flip started 2026-08-28, ticket had none of the four set):
   `fields = {"customfield_10015":"2026-08-28", "duedate":"2026-08-29",
              "customfield_10178":"2026-08-29", "customfield_10179":0.25}`.

   If all four are already filled, skip the write entirely and say so in the report.

3. **Confirm before writing** (outward write) via AskUserQuestion — preview which fields are empty
   and the value each will get. Skip the prompt only if the user explicitly asked to auto-fill.

4. **Move the chain to In Progress — THIS is the moment status changes.** Status is deliberately NOT
   touched at clone time (`[[jira-clone-btbs-els]]` leaves everything in To Do). It moves only now,
   because a *doing / voc / create-script* command was issued. Transition every not-yet-started
   ticket in the chain: the **working ticket** and the **source BTBS** it came from, found in
   `issuelinks` under either **`Blocks`** (outward `blocks`) or **`Cloners`** (outward `clones`) —
   see Step 1 for the lookup. If the working
   ticket is an older Subtask, also transition its **parent** if it has not started. Transition IDs
   differ per board: **ELS "In Progress" = 21**, **BTBS "IN PROGRESS" = 2** — fetch with
   `jira_get_transitions` if unsure. Skip any already In Progress or further along.

5. **The branch, commit and PR reference `jira_key`** for the `VOC(<jira_key>):` title and the
   migration folder. If the working ticket is an older Subtask, use its **parent** key for the PR
   title instead, so the PR still points at the parent-level issue.

### Step 1 — Load the ticket & collect SQL

Read the ticket: `mcp__mcp-atlassian__jira_get_issue(issue_key=jira_key, fields="*all", comment_limit=50)`. Extract summary, description, attachments, and **every fenced ```` ```sql ```` block across all comments** (a ticket may carry several — e.g. "Tháng 4" / "Tháng 5" as separate comments, like ELS-2093).

**Also read the linked BTBS source ticket.** An ELS VOC is usually only a summary of the original
request: the ELS issue commonly has **zero attachments**, while the room codes / promotion codes /
booking lists needed to write the SQL live as spreadsheets on the **BTBS** issue. Follow the link and
read it before deciding there is not enough information.

Find the BTBS key in the ELS ticket's `issuelinks` — it appears under either link type, so check both:
- **`Blocks`** — outward `blocks` → the BTBS issue (e.g. ELS-3374 *blocks* BTBS-1249)
- **`Cloners`** — outward `clones` → the BTBS issue (e.g. ELS-3257 *clones* BTBS-1218)

The ELS description often names it too ("Source VOC: BTBS-1249"), but resolve from `issuelinks` — it
is structured and always present when the link exists. If a link points at another **ELS** issue
rather than a BTBS one, follow that as well; a VOC can be cloned from an earlier ELS VOC (ELS-3293
clones ELS-3226 *and* blocks BTBS-1202).

Then fetch it — `jira_get_issue(<BTBS-KEY>, fields="summary,description,attachment,comment", comment_limit=50)`
— and harvest:
- the **original request wording** from the reporter (the PIC, e.g. Naoki), which carries intent the
  ELS summary drops
- **attachments** — the `.xlsx` / `.csv` lists of hotel, room, plan and promotion codes that the SQL
  has to target, plus red-boxed screenshots showing exactly what to change
- **comments** — clarifications and follow-up corrections agreed with the requester

Download an attachment you need with `jira_download_attachments(<BTBS-KEY>)`, or read a spreadsheet's
codes directly. **Never invent codes** that are only present in an attachment you have not opened — if
a needed file cannot be read, stop and say so rather than guessing.

If the ELS ticket has no BTBS link and no SQL, treat it as under-specified: ask the user before
generating anything.

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
- **Schedule fields**: which of Start date / Due date / Stg release date / Estimated duration were empty and got filled this run — or "already set, unchanged" when nothing needed backfilling
- **Status**: which tickets were transitioned to In Progress (working ticket / parent / original BTBS), or "already started"
- **Source BTBS**: `<BTBS-KEY>` and which of its attachments/comments the SQL was built from — or "none linked"
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

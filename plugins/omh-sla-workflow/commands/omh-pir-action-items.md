# Create PIR Action-Item Tickets (OMH SLA Policy §7.5.1 #3)

**Usage**: `/omh-pir-action-items <PIR-JIRA-KEY>`

Example: `/omh-pir-action-items ELS-1647`

Parse arguments from: $ARGUMENTS
- First `^[A-Z]+-[0-9]+$` token (or Jira URL) → **pir_key**

Turns the prevention/action-item table inside a PIR into **real, linked Jira tickets** — the single most common thing reviewers demand and authors forget. For each action item it creates a Jira issue with Owner, Priority, and a committed ETA (due date), then links it back to the PIR via `Relates`.

---

## Rules (from SLA Policy §7.5 + §7.5.1)

- **Every prevention action item must be its own Jira ticket** linked to the PIR via `Relates` (§7.5.1 #3) — no action items left as prose
- Each ticket needs a **committed ETA** (a real due date, weekly granularity minimum) — **never `TBD`**, especially for `Critical` items (§7.5.1 #2)
- Each ticket has an **Owner** and a **Status**; Owner roles use Part Lead / Dev Manager / Engineer naming (§7.5.1 #4, §15)
- Action items map to the PIR's **Validation Criteria** so completion conditions are unambiguous (§7.5.1 #2)
- This skill **reads the PIR as source of truth** — it does not invent action items; if the table is empty/missing it stops and points back to `/omh-create-pir`

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended, bundle independent questions (max 4). Each Jira create + link is an outward action → preview + confirm, description prefixed `"PUBLISHES: "`. Creating N tickets is confirmed as a batch (with the full list shown) plus a per-item review chance — see Step 3.

---

## Workflow

### Step 1 — Load the PIR & extract action items

`jira_get_issue(issue_key=pir_key, fields="*all", comment_limit=50)`. Locate the PIR `.md` (attachment preferred, else inline). Parse the **Prevention / Action Items** table into rows: `{n, action, owner, priority, eta, status, validation, existing_jira}`.

When parsing the `eta` cell: extract the first `\d{4}-\d{2}-\d{2}` date if the cell wraps the date in justification prose (e.g. *"Due to this take time for test so setup ETA to 2026-06-02"* → `2026-06-02`). Use the extracted date as the due date, but **flag the cell as needing cleanup** (the doc should hold a bare date per §7.5.1 #2) so it surfaces in the report. Only treat an ETA as missing/`TBD` when no parseable date exists at all.

- If no action-item table is found → stop: *"No action-item table in <pir_key>. Add one via /omh-create-pir, then re-run."*
- Cross-check existing `Relates` links: if an action item already has a linked ticket, mark it **already created** and exclude from the create set (idempotent — safe to re-run).

### Step 2 — Validate each item (no TBD, has owner)

For each item to be created, check ETA and Owner. If any is missing/`TBD`, gather the fixes in ONE AskUserQuestion call (max 4 at a time; loop if more):

```
AskUserQuestion (bundled, per incomplete item):
  Q (ETA):   question: "Action #<n> '<action>' has no committed ETA. Set one:"
             header: "ETA #<n>"
             options:
               - "1 week (YYYY-MM-DD)" (Recommended) — description: "Weekly granularity per §7.5.1"
               - "2 weeks (YYYY-MM-DD)" — description: "…"
               - "End of sprint (YYYY-MM-DD)" — description: "…"
               # user can type a custom date via Other
  Q (Owner): question: "Owner for action #<n>?"
             header: "Owner #<n>"
             options:
               - "Engineer (assignee)" (Recommended) — description: "Implementing engineer"
               - "Part Lead" — description: "…"
               - "Dev Manager" — description: "…"
```

> **Critical-item rule (§7.5.1 #2):** if a `Critical` item still has no ETA after the prompt, do NOT create it with a blank due date — require either a committed ETA or an explicit note documenting why one cannot be set yet. Surface this rather than silently creating an undated Critical ticket.

### Step 3 — Confirm the batch, then create

Show the full table of tickets about to be created (action, type, priority, owner, due date, validation) and confirm:

```
AskUserQuestion:
  question: "Create these <N> action-item tickets and link them to <pir_key>?"
  header:   "Create N"
  options:
    - "Create all <N>" (Recommended) — description: "PUBLISHES: N new ELS tickets, each linked Relates → <pir_key>"
    - "Let me pick which" — description: "Multi-select which items to create now"
    - "Cancel" — description: "Create none"
```

For "Let me pick which", use a `multiSelect: true` question listing the items.

For each selected item (use the PIR's own project key — the prefix of `pir_key` — never hardcode):
- `jira_create_issue(project_key=<from pir_key>, issue_type=<"Task" default; "Bug" if the action fixes a defect>, summary=<action>, description=<action detail + "Validation: <criterion>" + "Source PIR: <pir_key>">, additional_fields='{"labels":["pir-action"],"priority":{"name":"<mapped>"},"duedate":"<ETA>"}')` — `additional_fields` is a **JSON string**; add `assignee` as a top-level arg if known.
- `jira_create_issue_link(link_type="Relates to", inward_issue_key=<pir_key>, outward_issue_key=<new key>)` (falls back to "Relates" if rejected).
- Map priority: Critical→Highest, High→High, Medium→Medium, Low→Low.

If a create fails (permission, field required) → surface the error for that item, continue with the rest, and list failures at the end. Do not retry blindly.

### Step 4 — Offer to update the PIR doc's Jira column

After creation, the PIR table's `Jira` column should reference the new keys (so the doc and tickets stay in sync). Offer:

```
AskUserQuestion:
  question: "Post a comment on <pir_key> mapping each action item to its new ticket?"
  header:   "Sync doc"
  options:
    - "Post mapping comment" (Recommended) — description: "PUBLISHES: comment listing 'Action #n → ELS-xxxx' for traceability"
    - "Skip" — description: "I'll update the doc myself"
```

(We post a comment rather than editing the attached `.md` in place, since attachments aren't edited via MCP — note this to the user.)

### Step 5 — Report

- **Created**: list of `ELS-xxxx — <action> — <priority> — due <ETA> — Relates → <pir_key>`
- **Already existed**: items skipped as idempotent
- **Failed / needs attention**: any creates that errored, and any Critical items left without an ETA (with the §7.5.1 note)
- **Next**: re-run `/omh-review-pir <pir_key>` — gate G7 (action items linked) should now PASS

---

## Hard refusals

- Do NOT invent action items not present in the PIR — read them from the document
- Do NOT create a `Critical` action-item ticket with a blank/`TBD` due date (§7.5.1 #2) — require an ETA or a documented reason
- Do NOT create tickets without the Step 3 batch confirm
- Do NOT use owner role names other than Part Lead / Dev Manager / Engineer (§15)
- Do NOT close or transition the PIR (sign-off is human, §7.5)

---

## What this skill does NOT do

- Does not author the PIR or its action-item table (use `/omh-create-pir`)
- Does not score the PIR (use `/omh-review-pir`)
- Does not implement the fixes — it tracks them as tickets
- Does not manage on-call or incident declaration (use `/omh-incident-triage`)

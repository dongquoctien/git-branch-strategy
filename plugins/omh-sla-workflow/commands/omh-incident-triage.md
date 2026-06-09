# Triage / Declare an Incident (OMH SLA Policy §2, §3, §7)

**Usage**: `/omh-incident-triage [description-or-JIRA-KEY] [severity]`

Examples:
- `/omh-incident-triage "booking API 5xx spiking"` — classify a new incident
- `/omh-incident-triage ELS-1734` — triage/classify an existing ticket
- `/omh-incident-triage "payment gateway down" P0` — pre-set severity

Parse arguments from: $ARGUMENTS
- A `^[A-Z]+-[0-9]+$` token (or Jira URL) → **incident_key** (existing ticket)
- A `P0|P1|P2|P3` token → **severity**
- Remaining free text → **description**

The front door of the incident process: assign severity (§2), compute the SLA response/resolution deadlines (§3), start the minute-by-minute timeline log (§7 step 3), and — for P0 — surface the P0 Response Protocol checklist. It sets up everything `/omh-create-pir` later consumes.

---

## Rules (from SLA Policy §2, §3, §7)

- Severity assigned at detection by the on-call engineer; escalation by Part Lead / Dev Manager; **downgrades require Dev Manager approval** (§2)
- **When in doubt, escalate** — over-prioritize rather than under-prioritize (§2)
- SLA clocks (§3.1): P0 = respond 10 min / resolve 1 h / update every 15 min; P1 = 20 min / 4 h / 30 min; P2 = 2 h / 1 business day / 4 h; P3 = 4 h / 3 business days / as needed
- **MTTD starts at the earliest detection event** (alert, user report, or internal) — not ticket-creation time (§7 step 1, §10)
- On classification, capture **impact scope** (users, systems, revenue) and **incident owner** (§7 step 2)
- **P0 → activate P0 Response Protocol** immediately (§7): notify Dev Group, contact Part Lead, status update every 15 min
- A PIR will be required for P0 and major P1 (§7.5) — flag it at triage time
- This skill does not deploy fixes or approve changes — those follow §5 change control

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended, bundle independent questions (max 4). Any Jira write (create incident ticket, post status comment) is outward → preview + confirm, description prefixed `"PUBLISHES: "`. This skill is advisory until a confirmed write.

---

## Workflow

### Step 1 — Load or describe the incident

If `incident_key` given → `jira_get_issue(issue_key=incident_key, fields="*all", comment_limit=20)`; use its summary as the description.
Else use the free-text `description`. If neither present, ask for a one-line description (free text via AskUserQuestion "Other").

### Step 2 — Assign severity (§2)

If `severity` not in args, ask — anchor each option to the §2 definition + §3 SLA so the choice is informed:

```
AskUserQuestion:
  question: "Classify incident severity (§2). When in doubt, escalate."
  header:   "Severity"
  options:
    - "P1 — High" (Recommended) — description: "Major functionality, no workaround · respond 20m / resolve 4h"
    - "P0 — Critical" — description: "System down / revenue impact · respond 10m / resolve 1h · P0 Protocol + PIR"
    - "P2 — Medium" — description: "Partial, workaround exists · respond 2h / resolve 1 business day"
    - "P3 — Low" — description: "Minor · respond 4h / resolve 3 business days"
```

> Default-highlight P1 (not P0) as Recommended for an unclassified incident, but make P0's consequences explicit. The user's own read of impact decides. Note that downgrading later needs Dev Manager approval (§2).

### Step 3 — Capture detection time, impact scope, owner

Bundle into ONE AskUserQuestion call where free-text is expected (use "Other"):

- **Detection source & time** (drives MTTD per §7/§10): alert / user report / internal — and the earliest timestamp.
- **Impact scope**: which systems/flows (search, booking, payment, admin, extranet), rough % users, revenue exposure.
- **Incident owner**: who owns resolution.

For any value the user doesn't have yet, record `⚠️ TODO` — never fabricate a detection time (it corrupts MTTD).

### Step 4 — Compute SLA deadlines (§3.1)

From the detection/acknowledgment time and the chosen severity, compute and display:
- **Respond by**: detection + response target
- **Resolve by**: detection + resolution target
- **Update cadence**: per severity
- **Breach action**: per §3.1 (e.g. P0 → auto-escalate Dev Manager + CTO)

Present as a small table. These are advisory reminders, not timers the skill enforces.

### Step 5 — P0 Response Protocol (only if P0)

If P0, display the §7 protocol as an actionable checklist (do not auto-execute — these are human/comms actions):
1. Create urgent notification on Dev Group (Team Chat + Phone — §14)
2. Contact Part Lead by chat/phone (L2, ≤15 min — §16)
3. Post status updates every 15 min until resolved
4. Notify Dev Manager + CTO per §14 / §16 escalation

### Step 6 — Offer to create / update the incident ticket

```
AskUserQuestion:
  question: "Create the incident ticket (or update <incident_key>) with this triage?"
  header:   "Write tkt"
  options:
    - "Create incident ticket" (Recommended) — description: "PUBLISHES: new ELS ticket, severity label, impact + SLA deadlines + timeline stub"
    - "Post triage as comment" — description: "PUBLISHES: add triage summary to <incident_key>"  # if incident_key given
    - "Don't write — just show me" — description: "Advisory only"
    - "Cancel" — description: "Stop"
```

On create (use the existing ticket's project if `incident_key` was given, else ask for the project key — never hardcode):
- `jira_create_issue(project_key=<project>, issue_type="Task", summary=<description>, description=<triage block: severity, detection 4-timestamp stub, impact, owner, SLA deadlines, empty minute-by-minute timeline table>, additional_fields='{"labels":["incident","<severity-lowercased>"],"priority":{"name":"<P0→Highest,P1→High,P2→Medium,P3→Low>"}}')` — `additional_fields` is a **JSON string**.
- The description seeds the **minute-by-minute timeline table** (§7 step 3) and the **4 detection timestamps** so a later PIR inherits them.

### Step 7 — Report + handoff

- **Incident**: `<key>` — severity `<P0..P3>`
- **SLA**: respond by `<…>`, resolve by `<…>`, update every `<…>`, breach → `<…>`
- **⚠️ TODO**: any unconfirmed detection time / impact numbers
- **PIR required?**: Yes for P0 and major P1 → after resolution run `/omh-create-pir <key>`
- **Next**: keep the timeline log updated in the ticket; on resolution, start the PIR within 1 business day (§7.5)

---

## Hard refusals

- Do NOT fabricate the detection timestamp or MTTD — it must come from a real event (§7/§10); use `⚠️ TODO`
- Do NOT downgrade an existing incident's severity — that requires Dev Manager approval (§2); surface it instead
- Do NOT auto-execute the P0 Response Protocol comms (notifying CTO etc.) — present the checklist; humans act
- Do NOT create/update a ticket without the Step 6 confirm
- Do NOT approve deployments or hotfixes — that's §5 change control (and the git plugin's `/omh-hotfix`)

---

## What this skill does NOT do

- Does not write or review the PIR (use `/omh-create-pir`, `/omh-review-pir`)
- Does not manage on-call rotation or paging (that's the Dev Manager's PIC file, §4.3)
- Does not perform the hotfix/rollback (use git plugin `/omh-hotfix`, `/omh-rollback`)
- Does not aggregate metrics (use `/omh-sla-report`)

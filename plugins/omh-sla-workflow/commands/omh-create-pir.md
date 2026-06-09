# Create a Post-Incident Review (OMH SLA Policy §7.5)

**Usage**: `/omh-create-pir [incident-JIRA-KEY] [severity]`

Examples:
- `/omh-create-pir ELS-1734` — build a PIR from an existing incident ticket
- `/omh-create-pir ELS-1734 P0` — pre-set severity

Parse arguments from: $ARGUMENTS
- First `^[A-Z]+-[0-9]+$` token (or Jira URL) → **incident_key** (the incident this PIR is for)
- A `P0|P1|P2|P3` token → **severity**

This skill scaffolds a **review-ready** PIR: it creates the PIR Jira ticket (Task, label `pir`), drafts the PIR `.md` document from the standard template, and attaches the draft to the ticket. It is built so the PIR passes `/omh-review-pir` and Dev Manager + Part Lead sign-off on the first round — encoding the gates reviewers repeatedly enforce.

---

## Rules (from SLA Policy §7.5 + §7.5.1)

- PIR is **required for all P0 and major P1 incidents** (§7.5)
- Must be **created AND closed within 1 business day** of resolution (§7.5 deadline)
- **Owner sign-off = Dev Manager + Part Lead** — both required to close (§7.5, §15 RACI: A=Dev Manager, R=Part Lead+Engineer)
- The PIR document MUST contain: Timeline · 4-timestamp Detection block · 5-Whys (≥3 levels) · quantified Impact · Detection gap · Prevention action items · Owner sign-off (§7.5)
- **Detection uses 4 timestamps** — Event / Alert / Acknowledged / Response Start — and reports **MTTD (Event→Alert)** and **MTTA (Alert→Ack)** separately. Never a single vague MTTD. (§7.5.1 #2/#4-adjacent, §10)
- **Storage rule**: attach the `.md` to the Jira ticket — NEVER a personal SharePoint/OneDrive link (§7.5.1 #1)
- **Action items**: each gets a committed ETA (no `TBD`) + Status, and will become its own linked Jira ticket (§7.5.1 #2/#3) — this skill scaffolds them; `/omh-pir-action-items` creates the tickets
- **Roles** named in the doc must be exactly **Part Lead** / **Dev Manager** (§7.5.1 #4, §15)
- **Impact** must be quantified — revenue estimate, % users, duration (§7.5.1 #5)
- Severity, response/resolution, and any breach notes must align with §2 + §3 (§7.5.1 #6)

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
- **Every Jira write (create ticket, post comment, attach file) is an outward action** — show a preview and confirm via AskUserQuestion before executing (description prefixed `"PUBLISHES: "`)

---

## Workflow

### Step 1 — Load the incident

If `incident_key` provided, call `mcp__mcp-atlassian__jira_get_issue(issue_key=incident_key, fields="*all", comment_limit=50, expand="changelog")`. Extract: summary, description, priority, status, created, resolutiondate, comments (the minute-by-minute timeline lives here), attachments, issuelinks, assignee.

If no `incident_key`:
```
AskUserQuestion:
  question: "No incident ticket given. How do you want to start the PIR?"
  header:   "Source"
  options:
    - "Search incidents" (Recommended) — description: "I'll search recent P0/P1 incident tickets to pick from"
    - "Blank template" — description: "Draft a PIR from scratch; you'll fill incident facts manually"
    - "Cancel" — description: "Stop"
```
For "Search incidents", run `jira_search(jql="(labels in (systemissue, pir, incident) OR priority in (Highest, High)) AND statusCategory = Done ORDER BY resolutiondate DESC", limit=15)` (scope to a specific project with `projects_filter` or a `project = <KEY>` clause if the user names one) and present the top results as options.

### Step 2 — Confirm severity & PIR requirement

Determine `severity` from args, else from the incident `priority` (Highest→P0, High→P1, Medium→P2, Low→P3) — but ask to confirm, since SLA severity (§2) ≠ Jira priority field:

```
AskUserQuestion:
  question: "Confirm incident severity (drives SLA targets in §3)"
  header:   "Severity"
  options:
    - "P0 — Critical" — description: "System down / revenue impact · MTTR target <1h · PIR mandatory"
    - "P1 — High" — description: "Major functionality, no workaround · MTTR <4h · PIR for major P1"
    - "P2 — Medium" — description: "Partial, workaround exists · PIR optional"
    - "P3 — Low" — description: "Minor · PIR not required"
```

If P2/P3 selected, note that §7.5 only *requires* a PIR for P0 and major P1, and ask whether to proceed anyway (a voluntary PIR is fine; just flag it).

### Step 3 — Extract the timeline & detection timestamps

From the incident ticket's comments/changelog, reconstruct the timeline. Identify the **4 detection timestamps** (§7.5.1):
- **Event Time** — when the anomaly actually began (from metrics/logs, not the ticket creation time)
- **Alert Time** — when the automated alert fired (CloudWatch/Grafana/Prometheus)
- **Acknowledged Time** — when an engineer first acknowledged
- **Response Start Time** — when mitigation began

For any timestamp you cannot derive from the ticket, do NOT guess — mark it `⚠️ TODO: confirm` in the draft and list it in Step 6's gap report. Compute MTTD (Event→Alert) and MTTA (Alert→Ack) only when both ends are known; otherwise leave the formula with the unknown labeled.

### Step 4 — Draft the PIR document

Build the `.md` using this exact skeleton (fill from the incident; never invent numbers — use `⚠️ TODO` placeholders for unknowns):

```markdown
# PIR — <incident title>

| Field | Value |
|---|---|
| Incident ticket | <incident_key> |
| Severity | <P0/P1> (SLA §2) |
| Date of incident | <YYYY-MM-DD> |
| Author | <you> |
| Status | Draft — pending Part Lead + Dev Manager sign-off |
| SLA Resolution target | <from §3.1 for this severity> |
| SLA met? | <Yes/No — Resolution time vs target; note breach per §3.1 if exceeded> |

## 1. Summary
<2–3 sentences: what broke, who was affected, how long, how it was resolved.>

## 2. Detection (4 timestamps — SLA §7.5.1)
| Timestamp | Time (GMT+7) | Source |
|---|---|---|
| Event Time (anomaly began) | <…> | <metric/log> |
| Alert Time (automated alert fired) | <…> | <CloudWatch/Grafana/Prometheus> |
| Acknowledged Time (engineer ack) | <…> | <who> |
| Response Start Time (mitigation began) | <…> | <…> |

- **MTTD (Event → Alert):** <…>  — *was automated detection late/absent?*
- **MTTA (Alert → Ack):** <…>  — *operational/on-call response gap?*

## 3. Timeline (minute-by-minute)
| Time | Event | Owner |
|---|---|---|
| … | … | … |

## 4. Impact (quantified — SLA §7.5.1 #5)
- Users affected: <count / % of traffic>
- Revenue impact estimate: <amount + basis>
- Total duration (Event → confirmed resolution): <…>
- Systems/flows affected: <search / booking / payment / …>

## 5. Root Cause — 5-Whys (≥3 levels, SLA §7.5)
1. Why did <symptom> happen? → …
2. Why did <that> happen? → …
3. Why did <that> happen? → …
   (continue until the true root cause)
**Root cause:** <one sentence.>

## 6. Detection Gap
- How was it found: <alert / user report / internal>
- Why automated detection did not catch it sooner: <…>

## 7. Prevention / Action Items (each → its own linked Jira ticket, SLA §7.5.1 #3)
| # | Action | Owner (Part Lead / Dev Manager / Engineer) | Priority | ETA (no TBD) | Status | Validation criterion | Jira |
|---|---|---|---|---|---|---|---|
| 1 | … | … | Critical/High/Med | YYYY-MM-DD | Open | … | <to be created> |

## 8. SLA Alignment (§2/§3)
- Assigned severity: <P0/P1> · Response target met: <Y/N> · Resolution target met: <Y/N>
- Breaches noted: <… or none>

## 9. Sign-off (SLA §7.5 — both required to close)
- [ ] Part Lead: __________  (date)
- [ ] Dev Manager: __________  (date)
```

Filename: `PIR_<ShortTopic>_<YYYY-MM-DD>.md` (kebab/underscore, dated — matches existing `PIR_ElastiCache_Memory_Spike_2026-05-22.md` convention). Write it to the current working directory by default.

### Step 5 — Create the PIR ticket + attach (each write confirmed)

Show the drafted ticket fields and ask to create:

```
AskUserQuestion:
  question: "Create the PIR Jira ticket now?"
  header:   "Create tkt"
  options:
    - "Create PIR ticket" (Recommended) — description: "PUBLISHES: new Task in ELS, label 'pir', linked to <incident_key>"
    - "Just save the .md locally" — description: "No Jira write; I'll attach it myself"
    - "Cancel" — description: "Stop"
```

On confirm:
- **Project key**: default to the incident's own project (the prefix of `incident_key`, e.g. `ELS`). If starting blank with no incident, ask the user for the project key — never hardcode it.
- `jira_create_issue(project_key=<project>, issue_type="Task", summary="Create PIR Report for <incident>", description=<the PIR description template, §7.5 sections, in Markdown>, additional_fields='{"labels":["pir"]}')` — note `additional_fields` is a **JSON string**.
- Link it to the incident: `jira_create_issue_link(link_type="Relates to", inward_issue_key=<incident_key>, outward_issue_key=<new PIR key>)` (the link type is named "Relates to"; falls back to "Relates" if the instance rejects it).
- Attach the `.md`: per §7.5.1 #1, the file must live on the ticket. If the MCP cannot upload attachments, **do not** fall back to a personal-drive link — instead post the `.md` content inline as a comment and tell the user to attach the file manually (and explicitly warn against personal SharePoint).

### Step 6 — Report + gap list

Print:
- **PIR ticket**: `<key>` — linked to incident `<incident_key>`
- **Document**: `<filename>` (attached / saved locally)
- **⚠️ TODO list**: every `⚠️ TODO` placeholder still in the draft (unknown timestamps, unquantified impact, missing 5-Why levels) — the author must fill these before review
- **Next**: fill TODOs → `/omh-pir-action-items <PIR-key>` to create action-item tickets → `/omh-review-pir <PIR-key>` to self-audit → request Part Lead + Dev Manager sign-off
- **Deadline reminder**: §7.5 — PIR must be closed within 1 business day of resolution

---

## Hard refusals

- Do NOT store or link the PIR on a personal SharePoint/OneDrive/Google Drive (§7.5.1 #1) — attach to the ticket or post inline
- Do NOT invent timeline timestamps, MTTD/MTTA values, revenue figures, or user counts — use `⚠️ TODO` and surface them
- Do NOT collapse the 4 detection timestamps into a single vague MTTD (§7.5.1)
- Do NOT use role names other than Part Lead / Dev Manager / Engineer / CTO (§15)
- Do NOT create any Jira ticket/comment/link without an explicit confirm in the step
- Do NOT mark the PIR closed — closure requires human Part Lead + Dev Manager sign-off (§7.5)

---

## What this skill does NOT do

- Does not create the action-item tickets (use `/omh-pir-action-items`)
- Does not score/approve the PIR (use `/omh-review-pir`)
- Does not declare or triage the incident itself (use `/omh-incident-triage`)
- Does not produce the monthly roll-up (use `/omh-sla-report`)

# Draft the Monthly SLA Report (OMH SLA Policy §17)

**Usage**: `/omh-sla-report [YYYY-MM]`

Examples:
- `/omh-sla-report` — report for the prior calendar month (default)
- `/omh-sla-report 2026-05` — report for May 2026

Parse arguments from: $ARGUMENTS
- A `^\d{4}-\d{2}$` token → **period** (defaults to the prior month relative to today)

Assembles the **Monthly SLA Report** draft per §17: pulls the period's incidents and PIRs from Jira, computes the KPI roll-up (MTTD / MTTR / availability / compliance / deployment metrics), and produces a Markdown report with the §17.1 section layout. Output is a draft for the **Dev Manager** to review and own — this skill never publishes it as the official report.

---

## Rules (from SLA Policy §17 + §10)

- The Monthly SLA Report is **owned and produced by the Dev Manager**, sent to CTO, shared with the team, published by the **5th business day** of the month for the prior month (§17.1)
- Format is **Markdown** (`.md`); PDF distributed to Management (§17.2)
- Section layout (§17.1): Incident Summary · Severity Breakdown · MTTD · MTTR · Availability (B2C/Admin/Extranet) · SLA Compliance · Deployment Metrics · RCA Summary (links to all P0/P1 PIRs) · Open Action Items · Improvement Plan
- KPI definitions per §10; targets per §10.2 (SLA Compliance ≥95% / ≥99% P0-P1; P0 MTTR <1h; P1 MTTR <4h; MTTD <15m; B2C availability ≥99.9%; etc.)
- Numbers come from **Jira + monitoring**, not estimates — anything not derivable is marked `⚠️ source needed`, never fabricated
- This is a **draft generator** — the Dev Manager validates and owns the final report

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended, bundle independent questions (max 4). This skill is read-only on Jira and writes only a local `.md` draft. Sending/distributing the report is explicitly out of scope (no email/Slack writes) — it stops at producing the file.

---

## Workflow

### Step 1 — Resolve the period

Determine `period` from args or default to the prior calendar month. Show it and the date range (e.g. `2026-05-01 .. 2026-05-31`). Confirm only if ambiguous.

### Step 2 — Pull incidents & PIRs for the period

Run scoped Jira searches (read-only). Use `projects_filter` (or a `project = <KEY>` clause) to scope to the team's project — ask the user for the key if not already known; don't hardcode one:
- **Incidents**: `jira_search(jql="(labels in (incident, systemissue) OR priority in (Highest, High)) AND created >= '<start>' AND created <= '<end>' ORDER BY priority DESC", limit=50)`
- **PIRs**: `jira_search(jql="labels = pir AND updated >= '<start>' ORDER BY updated DESC", limit=50)`
- **Open action items**: `jira_search(jql="labels = pir-action AND statusCategory != Done ORDER BY duedate ASC", limit=50)`

For each incident, fetch enough fields to derive severity, created/resolved timestamps (for MTTR), and any breach notes.

### Step 3 — Compute KPIs (§10), flag missing sources

From the pulled data, compute what Jira supports and clearly mark what it doesn't:
- **Incident count** by severity (P0–P3) and **% change vs prior month** (run a second search for the prior period if the user wants the delta)
- **MTTR** per severity = mean(resolved − created) — derivable from Jira timestamps
- **SLA Compliance** = % resolved within the §3.1 resolution target per priority
- **MTTD / MTTA / Availability / Deployment success / Change-failure rate**: these need **monitoring sources** (Grafana/CloudWatch/CI), not Jira alone — emit `⚠️ source needed: <Grafana|CloudWatch|CI>` rather than guessing. Offer to let the user paste the numbers:

```
AskUserQuestion:
  question: "Availability & MTTD come from monitoring, not Jira. How to fill them?"
  header:   "Metrics src"
  options:
    - "Leave as '⚠️ source needed'" (Recommended) — description: "Dev Manager fills from Grafana/CloudWatch before publishing"
    - "I'll paste the numbers now" — description: "Enter availability/MTTD via Other"
```

### Step 4 — Build the report draft

Write `SLA_Report_<period>.md` with the §17.1 layout:

```markdown
# Monthly SLA Report — <period>
Owner: Dev Manager · Coverage: <start>..<end> · Generated: <date> · Status: DRAFT (pending Dev Manager review)

## 1. Incident Summary
Total incidents: <n> (<Δ% vs prior month>)

## 2. Severity Breakdown
| Severity | Count | % of total | Δ vs prior |
|---|---|---|---|
| P0 | … | … | … |
…

## 3. MTTD  (target <15 min, §10.2)
| Severity | Avg | Worst | vs target |
… (⚠️ source needed: Grafana/CloudWatch if not provided)

## 4. MTTR  (P0 <1h, P1 <4h, §10.2)
| Severity | Avg | Worst | vs target |
… (from Jira open→close)

## 5. Availability  (B2C ≥99.9%, Admin/Extranet ≥99.5%)
| System | Availability | Target | Met? |
… (⚠️ source needed: CloudWatch)

## 6. SLA Compliance  (≥95%, ≥99% P0/P1)
| Priority | Resolved in SLA | Total | Compliance % |
…

## 7. Deployment Metrics
Total deploys · Success rate · Rollbacks · Change failure rate
(⚠️ source needed: CI/CD + Jira tags)

## 8. RCA Summary (P0/P1 PIRs this period)
| PIR | Incident | Severity | Status | Link |
…  (links to the Jira PIR tickets)

## 9. Open Action Items (from current + prior PIRs)
| Ticket | Action | Owner | Priority | Due | Status |
… (overdue items flagged ⚠️)

## 10. Improvement Plan
<recurring themes across PIRs; planned actions for SLA misses>
```

### Step 5 — Report

- **Draft file**: `SLA_Report_<period>.md` (local)
- **Coverage**: counts pulled (incidents, PIRs, open action items)
- **⚠️ source-needed list**: every KPI awaiting a monitoring number
- **Overdue action items**: any past `duedate` and not Done (feeds §7.5 escalation)
- **Next**: Dev Manager fills monitoring metrics → reviews → exports PDF → distributes per §17.2. Reminder: publish by the **5th business day** (§17.1).

---

## Hard refusals

- Do NOT fabricate availability, MTTD, deployment, or revenue numbers — mark `⚠️ source needed` (§10 measurement sources)
- Do NOT send, email, or post the report anywhere — distribution is the Dev Manager's, this skill only drafts (§17.2)
- Do NOT mark the report final/published — it is always a DRAFT pending Dev Manager review (§17.1 ownership)
- Do NOT modify incident or PIR tickets — this skill only reads them

---

## What this skill does NOT do

- Does not create or review PIRs (use `/omh-create-pir`, `/omh-review-pir`)
- Does not create action-item tickets (use `/omh-pir-action-items`)
- Does not declare incidents (use `/omh-incident-triage`)
- Does not pull monitoring data directly (no Grafana/CloudWatch MCP assumed) — surfaces what to fill in

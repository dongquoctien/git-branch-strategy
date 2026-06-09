# Review a Post-Incident Review (OMH SLA Policy §7.5 + §7.5.1)

**Usage**: `/omh-review-pir <PIR-JIRA-KEY>`

Example: `/omh-review-pir ELS-1647`

Parse arguments from: $ARGUMENTS
- First `^[A-Z]+-[0-9]+$` token (or Jira URL) → **pir_key**

A **read-first audit** of a PIR against the exact gates that Dev Manager / Part Lead reviewers repeatedly enforce. Produces a scorecard with PASS / FAIL / N/A per gate and the precise reason. By default it only reads and reports; posting the review as a Jira comment is an explicit, confirmed action at the end.

---

## Rules (the audit checklist — from SLA Policy §7.5 + §7.5.1)

The PIR must satisfy ALL of these. Each maps to a real recurring review failure:

| # | Gate | What FAIL looks like | §ref |
|---|---|---|---|
| G1 | **Required sections present** | Missing Timeline / Detection / Root cause / Impact / Detection gap / Prevention / Sign-off | §7.5 |
| G2 | **4 detection timestamps** | Single vague MTTD; Event/Alert/Ack/Response-Start not all present | §7.5.1 |
| G3 | **MTTD & MTTA computed separately + consistent** | MTTD and MTTA conflated; gap (e.g. 5 min) not attributed to alert-latency vs response-latency; OR MTTD/MTTA quoted with **different values in different sections** | §7.5.1, §10 |
| G4 | **5-Whys ≥ 3 levels** | Root cause is 1 line / 1 level; no causal chain | §7.5 |
| G5 | **Impact quantified** | "performance degraded" with no users %, no revenue estimate, no duration | §7.5.1 #5 |
| G6 | **Action items have ETA + Status** | Any `ETA = TBD`, especially on `Critical` items; missing Status; OR an ETA that is not an explicit `YYYY-MM-DD` date in its own column (prose/range/justification text instead) | §7.5.1 #2 |
| G7 | **Action items are linked Jira tickets** | Items exist only as prose in the doc; no `Relates` links | §7.5.1 #3 |
| G8 | **Storage on the ticket, not personal drive** | PIR shared via personal SharePoint/OneDrive link | §7.5.1 #1 |
| G9 | **Correct role names** | "Engineering Manager"/"Tech Lead" instead of Part Lead / Dev Manager | §7.5.1 #4, §15 |
| G10 | **SLA alignment** | Severity/response/resolution don't match §2/§3; breaches not noted | §7.5.1 #6, §3.1 |
| G11 | **Sign-off block** | No Part Lead + Dev Manager sign-off lines (both required to close) | §7.5, §15 |
| G12 | **Deadline** | Resolved >1 business day ago and PIR still open/unclosed | §7.5 deadline |

---

## Interaction convention — ALWAYS use AskUserQuestion

`header` ≤12 chars, 2–4 options, first = recommended, bundle independent questions (max 4). Any Jira write (posting the review comment) is an outward action → preview + confirm, description prefixed `"PUBLISHES: "`. This skill is **read-only until the final optional comment step**.

---

## Workflow

### Step 1 — Load the PIR

`jira_get_issue(issue_key=pir_key, fields="*all", comment_limit=50, expand="changelog")`. Gather: description, comments, attachments (the PIR `.md`), issuelinks (action-item tickets), labels, status, created, resolutiondate, and the linked incident if present.

- If the ticket isn't a PIR (no `pir`/`systemissue` label and title doesn't match "PIR"), warn and ask whether to continue anyway.
- Locate the PIR document: prefer an attached `.md`; else the inline PIR content in description/comments. **If the only copy is a personal SharePoint/OneDrive link → that's an automatic G8 FAIL** (and you may not be able to read it; note that in the report).

### Step 2 — Run the 12 gates

For each gate G1–G12, classify PASS / FAIL / N/A and capture a one-line, specific reason quoting the offending text where possible. Specific guidance:

- **G2/G3**: confirm all 4 timestamps are real values; confirm MTTD and MTTA are stated as separate numbers with the correct formulas. If a single "MTTD ~0–5 min" appears without the breakdown → FAIL with the exact reviewer ask: *"clarify whether the gap reflects alert latency (MTTD) or post-ack response latency (MTTA)."* Also FAIL if MTTD (or MTTA) is quoted in more than one place with **different values** (e.g. "~2 min" in the summary but "~0–5 minutes" in the Detection section) — call out the conflicting locations; each metric must read as one consistent value document-wide.
- **G6**: scan the action-item table; any `TBD`/blank ETA → FAIL, and call out Critical items by name. Also FAIL if an ETA cell is not a clean `YYYY-MM-DD` date — e.g. a range, or a date buried in justification prose like *"Due to this take time for test so setup ETA to 2026-06-02"*. Quote the offending cell and note the date must sit alone in its own column.
- **G7**: cross-check each action item in the doc against the ticket's `Relates` links. Items with no corresponding Jira ticket → FAIL, list them. (Fix path = `/omh-pir-action-items`.)
- **G8**: search description + comments for `sharepoint.com`, `onedrive`, `personal`, `drive.google` → FAIL if the PIR lives there instead of an attachment.
- **G9**: grep for disallowed role strings.
- **G12**: compute business-day delta between `resolutiondate` of the incident and PIR closure; if >1 business day and not closed → FAIL.

### Step 3 — Score & report (read-only)

Print a scorecard:

```
PIR Review — <pir_key>: <title>
Severity: <P0/P1>   Incident: <incident_key>   PIR status: <status>

G1  Required sections ............ PASS
G2  4 detection timestamps ....... FAIL — Acknowledged Time missing; only Event+Alert present
G3  MTTD/MTTA separated .......... FAIL — single "MTTD ~0–5 min", no MTTA; attribute the 5-min gap
G4  5-Whys ≥3 levels ............. PASS (4 levels)
G5  Impact quantified ............ FAIL — no revenue estimate; "users affected" not %
G6  Action ETA + Status .......... FAIL — items #1,#3 (Critical) show ETA=TBD
G7  Action items linked .......... FAIL — 6 items in doc, 0 linked Jira tickets → run /omh-pir-action-items
G8  Stored on ticket ............. FAIL — PIR is a personal SharePoint link; attach .md to ticket
G9  Role names ................... PASS
G10 SLA alignment ................ PASS
G11 Sign-off block ............... PASS (Part Lead + Dev Manager lines present, unsigned)
G12 Deadline (≤1 business day) ... PASS

Verdict: 7/12 — NOT review-ready. 5 blockers above.
```

Then a prioritized **"Fix before requesting sign-off"** list (blockers first), each with the concrete action and the skill that fixes it where applicable.

### Step 4 — Offer to post the review as a Jira comment (optional, confirmed)

```
AskUserQuestion:
  question: "Post this review as a comment on <pir_key>?"
  header:   "Post review"
  options:
    - "Don't post — just show me" (Recommended) — description: "Read-only; I'll act on the findings myself"
    - "Post as Jira comment" — description: "PUBLISHES: adds the scorecard + fix list as a comment on <pir_key>"
    - "Cancel" — description: "Stop"
```

If "Post", format the scorecard as Jira markup and `jira_add_comment(issue_key=pir_key, comment=<scorecard>)`. Address it to roles, not by guessing usernames.

---

## Hard refusals

- Do NOT approve, sign off, or transition the PIR to Done — sign-off is a human Part Lead + Dev Manager decision (§7.5, §15)
- Do NOT modify the PIR document or ticket content — this skill audits, it doesn't edit
- Do NOT post any comment without the explicit Step 4 confirm
- Do NOT pass a PIR that stores its document on a personal drive (G8) — that's a hard FAIL regardless of content quality
- Do NOT invent values to make a gate pass — if data is missing, the gate FAILs with "data not present"

---

## What this skill does NOT do

- Does not create or edit the PIR (use `/omh-create-pir`)
- Does not create the action-item tickets it flags in G7 (use `/omh-pir-action-items`)
- Does not close the PIR or notify reviewers (human sign-off per §7.5)
- Does not aggregate metrics across PIRs (use `/omh-sla-report`)

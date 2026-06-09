# Software Development Team — Service Level Agreement (SLA) Policy

> **Authoritative source-of-truth** for the `omh-sla-workflow` plugin. Every SLA/PIR skill cites the `§` sections below. This is a working copy of the OhMyHotel & Co SLA Policy (v1.0, Effective April 2026); the canonical Notion page is the org master. When the two disagree, the Notion page wins — update this file and the skills together.

**Organization:** OhMyHotel & Co · **Owner:** Dev Manager · **Applies To:** Engineering, PD Team (QA), PD Team (BA)
**Review Cycle:** Monthly (Engineering) / Quarterly (Leadership) · **Version:** 1.0

---

## §2 Incident Severity (P0–P3)

Severity is assigned at detection time by the on-call engineer; may be escalated by Part Lead or Dev Manager. **Downgrades require Dev Manager approval.**

| Priority | Severity | Description | First Action |
|---|---|---|---|
| P0 | Critical | System down / booking unavailable / direct revenue impact | Immediate P0 Response Protocol — notify Dev Group |
| P1 | High | Major functionality impacted; no workaround | Escalate to Part Lead within 30 min |
| P2 | Medium | Partial functionality; workaround exists | Assign within 4 h; daily update |
| P3 | Low | Minor issue, low business impact | Triage in next sprint planning |

> **Priority Assignment Rule:** When in doubt, escalate — safer to over-prioritize.

## §3 SLA Response & Resolution Times

### §3.1 Incident SLA

| Priority | Response | Resolution | Update Freq | Breach Action |
|---|---|---|---|---|
| P0 | 10 min | 1 hour | Every 15 min | Auto-escalate to Dev Manager + CTO |
| P1 | 20 min | 4 hours | Every 30 min | Escalate to Part Lead + Dev Manager |
| P2 | 2 hours | 1 business day | Every 4 hours | Notify Dev Manager |
| P3 | 4 hours | 3 business days | As needed | No automated breach alert |

> **SLA Breach:** occurs when Response or Resolution time is exceeded for the assigned priority. Triggers automatic escalation. **All breaches must be noted in the PIR or incident Jira ticket.**

### §3.2 Bug Fix SLA

| Severity | Response | Fix Time | Resolution Path |
|---|---|---|---|
| Critical | 10 min | 1 hour | Hotfix branch + emergency deploy |
| High | 20 min | 4 hours | Hotfix branch; staging validation required |
| Medium | 2 hours | 3 business days | Standard PR flow |
| Low | 4 hours | Next sprint | Backlog grooming |

> **Regression Policy:** Any fix that introduces a regression is a new incident at the same or higher severity. The engineer who introduced it owns the fix.

## §4 Working Hours & On-Call

- **Business Hours:** Mon–Fri 07:00–18:00 (GMT+7).
- **Non-Touch Time:** all working hours — disruptive prod activities prohibited (hotfix deploys, heavy queries, schema/infra changes, any Medium+ risk) **without explicit CTO approval**. Only P0 emergency response is permitted.
- **Regular Deployment Window:** Tue & Thu 06:00–08:00 GMT+7 — the only exception to Non-Touch Time.
- **After-Hours On-Call:** applies only to P0 and critical P1. On-call Engineer ack ≤10 min (P0) / ≤20 min (P1); Part Lead ≤15 min (P0); Dev Manager ≤1 h (P0). If on-call is unreachable within the window, the Part Lead assumes the role automatically and it's logged for performance review.
- **Deployment PIC:** every prod deploy needs a named PIC, available for the full window, monitors ≥30 min post-deploy, can roll back immediately, listed in the Jira ticket before deploy.

## §5 Product Change Control

| Change Type | Approval Flow |
|---|---|
| Regular Deployment | Developer → Part Lead → Dev Manager *(final)* — deploy in Regular Window only |
| Hotfix | Developer → Part Lead → Dev Manager → **CTO approval required** |
| Emergency Change | Developer → Part Lead → Dev Manager → **CTO approval required** |

- CTO-unreachable exception (Hotfix/Emergency): if CTO unreachable within 15 min, Dev Manager may grant temporary approval and notify CTO immediately after; **must be documented in Jira with a timestamp**.
- **Every emergency change must be followed by a PIR within 1 business day**, and a retrospective change ticket created in Jira within 1 hour of the change.

### §5.3 Change Checklist (required in the Jira ticket)

- [ ] Description of change + business justification
- [ ] Staging test evidence (screenshot or CI pass link)
- [ ] Risk assessment (Low / Medium / High)
- [ ] Rollback plan documented
- [ ] Deployment PIC named
- [ ] Estimated deployment duration
- [ ] Monitoring plan post-deployment

## §6 Heavy Database Query / Data Operation

Applies to any prod operation ≥ 50,000 rows OR estimated duration > 120 s (Aurora/MySQL direct, INSERT-SELECT, full-table copy, large schema migration, BigQuery).

Mandatory: tested in Staging first · rollback plan in Jira · **CTO approval before prod** · run in the Regular Window · monitored in real time.
Flow: `Engineer writes query → Test in Staging → Part Lead review → Dev Manager review → CTO approval → Execute with monitoring`.
> Running a heavy query on prod without CTO approval is a policy violation, escalated to Dev Manager.

## §7 Incident Management Process

1. **Detection** — sources: CloudWatch / Grafana / Prometheus alerts, customer support, internal reports. **MTTD clock starts at the earliest detection event.**
2. **Classification** — on-call assigns Priority (P0–P3), impact scope (users / systems / revenue), incident owner. If P0 → activate P0 Response Protocol.
3. **Response** — assigned engineer acknowledges (MTTA stops), begins a **minute-by-minute timeline log in the Jira ticket**, posts first status update to the incident thread.
4. **Resolution** — apply fix, validate in staging/canary, deploy, confirm via monitoring (no recurrence within 15 min). MTTR stops at confirmed resolution.
5. **Post-Incident Review (PIR)** — see §7.5 below.

> **P0 Response Protocol:** (1) urgent notification on Dev Group; (2) contact Part Lead by chat/phone; (3) status updates every 15 min until resolved.

### §7.5 Post-Incident Review (PIR) — the core of this plugin

**Required for all P0 incidents and all major P1 incidents.**

A PIR must include:

- **Timeline** — minute-by-minute from detection to resolution.
- **Detection (4 timestamps)** — Event Time, Alert Time, Acknowledged Time, Response Start Time. Compute **MTTD = Event→Alert** and **MTTA = Alert→Ack** separately, so monitoring gaps and operational gaps are analyzed independently. Never state a single vague MTTD. **MTTD/MTTA must each appear as one consistent value across the whole document** — the same number wherever quoted (a value in the summary that disagrees with the Detection section is a defect to fix).
- **Root cause** — 5-Whys analysis, **minimum 3 levels deep**.
- **Impact** — users affected (count / %), revenue impact estimate (quantified, not vague), total duration.
- **Detection gap** — how it was found, why automated detection did not catch it sooner.
- **Prevention actions** — concrete corrective items, **each created as its own Jira ticket** and linked to the PIR.
- **Owner sign-off** — **Dev Manager + Part Lead approval required to close** the PIR.

> **PIR Deadline:** created AND closed within **1 business day** of resolution. Overdue PIRs escalate to Dev Manager; recurring overdue PIRs are flagged in the monthly Engineering Review.

### §7.5.1 PIR Storage & Action-Item Rules (hard rules — enforced by review-pir)

These are recurring review failures. A PIR is **not review-ready** until all pass:

1. **Storage** — the PIR `.md` is **attached directly to the Jira ticket** (or shared channel). **Never** a personal SharePoint/OneDrive link — those break when people leave or permissions change. A PIR is an organizational asset.
2. **Action-item ETA + status** — every action item has a committed ETA (weekly granularity minimum) and a Status. The ETA must be an **explicit calendar date** (`YYYY-MM-DD`) in its own column — not prose, not a range, not justification text wrapped around the date. **No `ETA = TBD`**, especially for `Critical` items. Each item maps explicitly to a Validation Criterion.
3. **Action-item Jira tickets** — every action item is a real Jira ticket, linked to the PIR via `Relates`. No action items left as prose only.
4. **Roles** — use exactly **Part Lead** and **Dev Manager** (not "Engineering Manager", "Tech Lead", etc.).
5. **Quantified impact** — revenue, % users, and duration are numbers, not adjectives.
6. **SLA alignment** — the PIR's severity, response/resolution times, and breach notes align with §2 and §3.

## §8 Deployment SLA

| Environment | Approver | Rollback |
|---|---|---|
| Production — Emergency | Dev Manager + CTO | Auto-rollback if error rate > 5% within 10 min |
| Production — Hotfix | Dev Manager + CTO | Rollback plan required before deploy |
| Production — Regular | PD (QA) sign-off + Part Lead + Dev Manager | Rollback plan required; smoke test mandatory |
| Staging | Engineer | Overwrite allowed |
| Dev | Engineer | Dev discretion |

> **Rollback Gate:** all prod deploys need a documented rollback plan in Jira before deploy begins. Emergency auto-rollback triggers if error rate > 5% within 10 min.

## §10 SLA KPIs

| KPI | Definition | Source |
|---|---|---|
| MTTD | Incident occurrence → first detection (earliest of alert / report / internal). | Grafana / CloudWatch timestamp |
| MTTR | Incident occurrence → confirmed resolution. | Jira open → close timestamp |
| MTTA | Alert → engineer acknowledgment. | Grafana ack timestamp |
| Availability | % of time operational. | CloudWatch uptime |
| SLA Compliance Rate | % of incidents resolved within SLA resolution time. | Jira SLA tracker |
| Change Failure Rate | % of changes that caused a prod incident. | Jira incident tags |
| Deployment Success Rate | % of deploys with no rollback/hotfix within 24 h. | CI/CD + Jira |

**Targets:** SLA Compliance ≥ 95% (≥ 99% P0/P1) · P0 MTTR < 1 h · P1 MTTR < 4 h · MTTD < 15 min · MTTA < 15 min · B2C Availability ≥ 99.9% · Admin/Extranet ≥ 99.5% · Deployment Success > 99% · Change Failure < 5%.

## §14 Communication Channels (PIR-relevant)

| Type | Channel | Notified |
|---|---|---|
| P0 Incident | Team Chat + Phone | All on-call + Part Lead + Dev Manager + CTO |
| P1 Incident | Team Chat + Jira ticket | Assigned engineer + Part Lead |
| Post Incident Review | Jira PIR ticket | Engineer + Part Lead + Dev Manager + CTO |

## §15 Roles & RACI (PIR-relevant rows)

| Process | Dev Manager | Part Lead | Engineer | PD (QA) | PD (BA) | CTO |
|---|---|---|---|---|---|---|
| Incident Detection & Triage | I | C | R | I | I | I |
| P0 Response Protocol | A | R | R | I | I | I |
| Incident Resolution | A | C | R | C | I | I |
| **PIR Creation & Closure** | **A** | **R** | **R** | I | I | I |
| SLA KPI Reporting | A | C | R | I | C | I |

(R = Responsible, A = Accountable, C = Consulted, I = Informed)

## §16 Escalation Matrix

| Level | Role | Response | Method |
|---|---|---|---|
| L1 | On-call Engineer | Immediate | Team Chat alert |
| L2 | Part Lead | 30 min | Team Chat + phone |
| L3 | Dev Manager | 1 hour | Phone / Team Chat |
| L4 | CTO | As needed (mandatory for Hotfix/Emergency/Heavy Query) | Phone |

## §17 SLA Reporting

- **§17.1 Monthly SLA Report** — produced by Dev Manager, sent to CTO, shared with the team, published by the 5th business day of each month for the prior month. Sections: Incident Summary · Severity Breakdown · MTTD · MTTR · Availability (B2C/Admin/Extranet) · SLA Compliance · Deployment Metrics · RCA Summary (links to all P0/P1 PIRs) · Open Action Items · Improvement Plan.
- **§17.2 Format:** Markdown (`.md`); PDF to Management. Owner: Dev Manager.
- **§17.3 Quarterly Leadership Review** — target revisions, capacity vs SLA, 3-month trends, policy proposals.

## §18 SLA Exclusions

Does not apply to: planned maintenance (announced ≥ 48 h ahead) · third-party outages (AWS, payment providers) · force majeure · customer-side config/network · decommissioned versions.

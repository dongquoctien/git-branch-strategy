# omh-sla-workflow

Claude Code plugin implementing the **OhMyHotel SLA Policy** — incident management and Post-Incident Reviews — as 5 interactive slash commands.

See [docs/SLA-POLICY.md](../../docs/SLA-POLICY.md) for the authoritative policy (§2–§18) that every skill cites.

## Commands at a glance

| Command | Purpose | Policy §§ |
|---|---|---|
| `/omh-incident-triage` | Classify a P0–P3 incident, compute SLA deadlines, start the timeline, P0 protocol | §2, §3, §7 |
| `/omh-create-pir` | Scaffold a review-ready PIR (4-timestamp detection, 5-Whys, action items) + ticket | §7.5 |
| `/omh-review-pir` | Read-only 12-gate audit of a PIR against recurring reviewer failures | §7.5, §7.5.1 |
| `/omh-pir-action-items` | Turn the PIR action-item table into linked Jira tickets with ETAs | §7.5.1 #3 |
| `/omh-sla-report` | Draft the Monthly SLA Report (KPI roll-up) for the Dev Manager | §17 |

## The PIR lifecycle these skills enforce

```
incident → /omh-incident-triage → (resolve) → /omh-create-pir
        → /omh-pir-action-items → /omh-review-pir → Part Lead + Dev Manager sign-off
monthly: /omh-sla-report
```

## Why these skills exist (the gates they enforce)

Real PIRs at OhMyHotel repeatedly fail review on the same points. These skills encode them so a PIR is review-ready on the first pass:

1. **No personal SharePoint** — the PIR `.md` is attached to the ticket; an org asset, not a personal drive link (§7.5.1 #1)
2. **Committed ETAs** — every action item has a real due date, no `TBD`, especially Critical items (§7.5.1 #2)
3. **Action items are linked Jira tickets** — not prose (§7.5.1 #3)
4. **4-timestamp detection** — Event / Alert / Ack / Response-Start → MTTD and MTTA computed separately (§7.5.1)
5. **Correct roles** — Part Lead / Dev Manager, not "Engineering Manager" (§7.5.1 #4)
6. **Quantified impact** — revenue, % users, duration (§7.5.1 #5)
7. **SLA alignment** — severity & timings match §2/§3 (§7.5.1 #6)

## Design principles (shared with omh-git-workflow)

- **UI-first prompts**: every input uses `AskUserQuestion`, never raw text
- **Confirm before writing to Jira**: every create-ticket / comment / attach is previewed and confirmed (`PUBLISHES:` prefix)
- **No fabricated data**: unknown timestamps, metrics, and impact numbers are marked `⚠️ TODO` / `⚠️ source needed`, never invented
- **No human sign-off bypass**: skills never close a PIR or mark a report final — that's Part Lead / Dev Manager
- **Read-first**: `/omh-review-pir` and `/omh-sla-report` don't mutate tickets

## Dependencies

- `mcp-atlassian` MCP server — Jira incident/PIR tickets, comments, links, attachments
- Monitoring numbers (MTTD, availability, deployment metrics) come from Grafana / CloudWatch / CI — surfaced for the Dev Manager to fill; not pulled automatically

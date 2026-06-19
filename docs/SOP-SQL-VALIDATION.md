# SOP — SQL Script Validation Before Production Execution

> **Authoritative source-of-truth** for the `/omh-voc-migration` skill. This is a working copy of the OhMyHotel & Co SOP "SQL Script Validation Before Production Execution"; the canonical doc is the org master. When they disagree, the org doc wins — update this file and the skill together.

**Purpose:** ensure all SQL scripts are validated in Staging and reviewed for performance and locking impact before execution on Production.

---

## §1 Scope

This SOP applies to any SQL that mutates Production data or schema:

- `UPDATE`
- `DELETE`
- `INSERT` (bulk data)
- `ALTER TABLE`
- Data Migration Scripts (incl. VOC data-fix scripts)

---

## §2 Prerequisites (mandatory before Production execution)

Any SQL script intended to run on Production must:

1. Have a **Jira ticket**.
2. Be **committed to the Git repository**.
3. Have a **Pull Request created and approved**.
4. Be **merged into the `master` branch before execution**.
5. Follow the standard **Git Strategy and Release process** (see `README.md`).

> **Hard rule:** Direct execution of SQL scripts on Production **without following the Git process is prohibited.**

---

## §3 Step 1 — Claude AI SQL Review

The developer must review the SQL script using **Claude Code AI** before submitting the Pull Request.

**Review scope:**

- Full Table Scan Risk
- Missing Index Risk
- Lock Risk
- Estimated Impact (rows affected, est. duration)
- Recommendations

**Required evidence:** the Claude AI review result must be **attached and included in the Pull Request description or comments**.

**Format example:**

```
Risk Level: Low / Medium / High
Summary:
- Index used: Yes
- Full Scan: No
- Lock Risk: Low
- Recommendation: Safe to execute
```

---

## §4 Step 2 — Execute on Staging

The developer must execute the **exact same SQL script** intended for Production on the **Staging** environment first.

**Required evidence:**

- SQL Script
- Execution Time
- Rows Affected
- Screenshot showing successful execution result
- CloudWatch screenshots after execution

**Recommended CloudWatch metrics:** `CPUUtilization`, `RowLockTime`, `CommitLatency`.

**Format example:**

```
Execution Time: 12 sec
Rows Affected: 12,543
Status: Success
```

---

## §5 Additional Requirement for Large Changes

- Large data operations must follow the standard Git Strategy process.
- Large SQL operations must be **executed in smaller batches** instead of a single large transaction.

---

## §6 Production Approval Checklist

A SQL script can only be approved for Production when **all** items below are completed:

1. [ ] Jira Ticket Created
2. [ ] SQL Script Committed to Git
3. [ ] Pull Request Approved
4. [ ] Merged to Master
5. [ ] Claude AI Review Attached in PR
6. [ ] SQL Executed on Staging
7. [ ] Execution Time Recorded
8. [ ] Rows Affected Recorded
9. [ ] Execution Screenshot Attached
10. [ ] CloudWatch Evidence Attached

> **Approval Rule:** Any SQL script missing one or more required evidence items above **must not be executed on Production.**

---

## Related policies

- **Git Strategy & Release** — `README.md` (branch naming §11, PR standards §13, review/merge §15).
- **SLA — Heavy Database Query / Data Operation** — `docs/SLA-POLICY.md` §6 (CTO approval, Regular Deployment Window, real-time monitoring) applies on top of this SOP when an operation is ≥ 50,000 rows or estimated > 120 s.

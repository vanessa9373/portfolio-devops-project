# Post-Mortem Report: [Incident Title]

## Metadata
| Field | Value |
|-------|-------|
| **Date** | YYYY-MM-DD |
| **Duration** | X hours Y minutes |
| **Severity** | SEV-1 / SEV-2 / SEV-3 |
| **Author** | [Your Name] |
| **Status** | Draft / Reviewed / Complete |
| **Services Affected** | [List services] |
| **Error Budget Impact** | X% of monthly budget consumed |

---

## Executive Summary
*2-3 sentences describing what happened, impact, and resolution.*

> On [date], [service] experienced [problem] for [duration], resulting in [impact].
> The root cause was [brief description]. The issue was resolved by [action].

---

## Impact
- **User-facing impact:** [What users experienced — errors, slowness, unavailability]
- **Duration of impact:** [Start time] to [End time] (total: X minutes)
- **Requests affected:** [Number or percentage of failed requests]
- **Error budget consumed:** [X% of monthly budget]
- **Revenue impact:** [If applicable]

---

## Timeline (All times in UTC)

| Time | Event |
|------|-------|
| HH:MM | [First sign of issue — metric spike, log entry] |
| HH:MM | [Alert fired — which alert, who was paged] |
| HH:MM | [Responder acknowledged alert] |
| HH:MM | [Initial investigation — what was checked first] |
| HH:MM | [Root cause identified] |
| HH:MM | [Mitigation applied — what action was taken] |
| HH:MM | [Service recovered — metrics returned to normal] |
| HH:MM | [All-clear declared] |

---

## Root Cause Analysis

### What happened
*Detailed technical explanation of the failure chain.*

### Why it happened
*Use the "5 Whys" technique to get to the root cause.*

1. **Why did [symptom] occur?** — Because [reason]
2. **Why did [reason] occur?** — Because [deeper reason]
3. **Why did [deeper reason] occur?** — Because [even deeper]
4. **Why?** — Because [systemic issue]
5. **Why?** — Because [root cause]

### Contributing factors
- [Factor 1 — e.g., missing monitoring, no alerts]
- [Factor 2 — e.g., insufficient testing, no canary deploy]
- [Factor 3 — e.g., documentation gap, unclear ownership]

---

## Detection
- **How was the incident detected?** [Alert / Customer report / Manual observation]
- **Time to detect (TTD):** [Minutes from start to detection]
- **Could we have detected it sooner?** [Yes/No — How?]

## Response
- **Time to respond (TTR):** [Minutes from alert to first responder action]
- **Time to mitigate (TTM):** [Minutes from response to mitigation]
- **Time to resolve (TTR):** [Minutes from mitigation to full resolution]
- **What went well in the response?** [List positives]
- **What could be improved?** [List areas for improvement]

---

## Mitigation & Resolution

### Immediate mitigation
*What was done to stop the bleeding?*
- [Action 1 — e.g., rolled back deployment]
- [Action 2 — e.g., scaled up replicas]

### Permanent resolution
*What was done to fully fix the issue?*
- [Fix 1 — e.g., fixed bug in code, deployed v1.2.4]
- [Fix 2 — e.g., increased resource limits]

---

## Lessons Learned

### What went well
- [Positive 1 — e.g., alerts fired quickly, team responded within SLA]
- [Positive 2 — e.g., runbook was helpful and accurate]

### What went poorly
- [Negative 1 — e.g., took too long to identify root cause]
- [Negative 2 — e.g., rollback process was manual and slow]

### Where we got lucky
- [Lucky 1 — e.g., happened during low-traffic hours]
- [Lucky 2 — e.g., a team member happened to be looking at dashboards]

---

## Action Items

| Priority | Action | Owner | Due Date | Status |
|----------|--------|-------|----------|--------|
| P0 | [Immediate fix — prevent recurrence] | [Name] | [Date] | Open |
| P1 | [Add missing monitoring/alerting] | [Name] | [Date] | Open |
| P1 | [Improve runbook with findings] | [Name] | [Date] | Open |
| P2 | [Long-term architectural improvement] | [Name] | [Date] | Open |
| P2 | [Add automated test for this failure mode] | [Name] | [Date] | Open |

---

## Appendix

### Relevant Graphs
*Include screenshots or links to Grafana dashboards showing the incident.*

### Related Incidents
*Link to any previous incidents with similar root cause.*

### References
*Links to PRs, commits, or documentation related to the fix.*

---

> **Reminder:** This is a *blameless* post-mortem. We focus on systems and processes,
> not individual mistakes. The goal is to learn and improve, not to assign blame.

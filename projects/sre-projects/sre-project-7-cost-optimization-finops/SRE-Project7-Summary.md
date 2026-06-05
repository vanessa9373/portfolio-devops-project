# SRE Project 7: Cloud Cost Optimization — Interview Summary

## The One-Liner
"I built a FinOps framework that automated cost visibility, rightsizing recommendations, and spot instance management — the kind of system that typically saves 30-60% on cloud spend."

---

## Situation
Cloud costs were growing unchecked. Teams had no visibility into per-service spend, instances were oversized, and nobody was using spot instances despite 60-90% savings potential. Budget overruns were discovered weeks late.

## Task
Build an automated cost optimization system that provides real-time visibility, enforces budgets, right-sizes resources based on actual usage, and safely implements spot instances for compute savings.

## Action

### 1. Cost Visibility Layer
- Deployed **AWS Cost & Usage Reports (CUR)** to S3 with hourly, resource-level granularity
- Set up **Cost Anomaly Detection** using AWS's ML-powered anomaly monitor — alerts within hours, not weeks
- Built **CloudWatch cost dashboard** showing spend by service, daily trends, and budget thresholds
- Enforced **cost allocation tags** so every resource is attributed to a team

### 2. Budget Governance
- Created **tiered AWS Budgets** — total ($500), EC2 ($200), EKS ($150), data transfer ($50)
- Configured **multi-threshold alerts** at 50%, 80%, 100%, and forecasted breach
- SNS notifications to team email — no more surprise bills

### 3. Automated Rightsizing
- Built a **Lambda function** running daily on CloudWatch Events
- Analyzes **14-day CPU utilization** for all running EC2 instances
- Under-utilized (<20% avg CPU): recommends downsizing
- Over-utilized (>80% avg): recommends upsizing
- Generates a **formatted report** sent via SNS with specific size recommendations
- Also pulls **AWS Cost Explorer rightsizing data** for cross-reference

### 4. Spot Instance Strategy
- Implemented a **mixed instance ASG** with on-demand base + spot burst capacity
- **Capacity-optimized allocation** — AWS selects pools with lowest interruption rate
- **Instance diversification** across 6 types (t3/t3a/m5/m5a) to reduce interruption risk
- Built a **graceful interruption handler** that polls the metadata endpoint for the 2-minute warning, then drains connections before shutdown

### 5. Kubernetes Cost Governance
- Applied **ResourceQuota** per namespace with tiered limits (prod > staging > dev)
- Set **LimitRange** defaults so every container has requests/limits even if devs forget
- Created analysis scripts to find pods without resource requests (cost blind spots)

## Result
- **Cost visibility**: From zero to real-time per-service spend tracking
- **Budget enforcement**: Alerts at 50/80/100% prevent surprise overruns
- **Rightsizing automation**: Daily scans catch over/under-provisioned instances within 24 hours
- **Spot savings**: 60-90% on burst compute with managed interruption handling
- **K8s governance**: ResourceQuotas prevent namespace sprawl and over-provisioning

---

## How to Talk About This in Interviews

### "How do you approach cloud cost optimization?"
"I follow FinOps principles: first visibility (CUR reports, cost dashboards, allocation tags), then accountability (per-team attribution), then optimization (rightsizing, spot instances), and finally governance (budgets, quotas). I automate everything — our rightsizing Lambda runs daily and our budget alerts fire at multiple thresholds so we catch issues early."

### "How do spot instances work and how do you handle interruptions?"
"Spot instances are spare EC2 capacity at 60-90% discount. The trade-off is AWS can reclaim them with 2 minutes notice. I handle this with: 1) capacity-optimized allocation strategy that picks the least-likely-to-be-interrupted pool, 2) diversification across 6 instance types to avoid single-pool risk, 3) on-demand base capacity for critical workloads, and 4) a graceful shutdown handler that detects the interruption notice, drains connections, and cleanly terminates."

### "How do you prevent Kubernetes cost sprawl?"
"Three layers: ResourceQuotas set hard caps per namespace so no team can consume unbounded resources. LimitRange sets defaults so every container has requests and limits even if developers don't specify them. And we run regular analysis scripts that identify pods without resource requests — those are cost blind spots because the scheduler can't pack efficiently."

### "How do you catch cost anomalies?"
"AWS Cost Anomaly Detection uses ML to learn our normal spending patterns and alerts when something deviates. We also have tiered budget alerts — 50% triggers awareness, 80% triggers investigation, 100% triggers action. The combination means we know about anomalies within hours, not at month-end."

---

## Technical Depth Questions

**Q: Why capacity-optimized instead of lowest-price for spot?**
A: Lowest-price picks the cheapest pool, but that's often the most contested pool with highest interruption rates. Capacity-optimized picks pools with the most available capacity, which means lower interruption rates. The price difference is usually marginal, but the reliability improvement is significant.

**Q: Why not use Savings Plans or Reserved Instances instead of spot?**
A: They're complementary, not alternatives. Reserved/Savings Plans cover your steady-state baseline (1-3 year commitment for 30-60% savings). Spot covers variable/burst workloads where you can tolerate interruptions. The mixed ASG uses on-demand for the base (could be covered by RIs) and spot for everything above.

**Q: How does the rightsizing Lambda avoid false positives?**
A: It looks at 14-day averages AND max CPU. A workload with 15% average but 90% max is probably bursty and correctly sized — the Lambda won't recommend downsizing because max_cpu > 50% threshold. It only flags instances where BOTH average is low AND peaks are modest.

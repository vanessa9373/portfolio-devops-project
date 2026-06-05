# Project 1: Multi-Region E-Commerce Platform

> **Role Focus:** AWS Solutions Architect  
> **Scenario:** Retail startup  
> **Complexity:** Advanced  

---

## 1. Real-World Problem

**ShopFast** is a direct-to-consumer retail startup launching flash sales every Friday at noon. Last quarter, a 10x traffic spike took the site down for 22 minutes — costing $140,000 in lost revenue. The engineering team needs a Solutions Architect to redesign the platform with the following requirements:

| Requirement | Target |
|-------------|--------|
| Availability | 99.99% (< 52 min downtime/year) |
| Recovery Time Objective (RTO) | < 15 minutes |
| Recovery Point Objective (RPO) | < 1 minute |
| Peak traffic | 50,000 concurrent users |
| Normal traffic | 5,000 concurrent users |
| Regions | Primary: us-east-1 / DR: us-west-2 |
| Compliance | PCI-DSS (card data) |

---

## 2. Architecture Overview

```
                         ┌─────────────────────────────────────┐
                         │           Global Layer               │
                         │                                     │
  Users ──────────────▶  │  Route 53 (Latency-based routing)   │
                         │          +  Health Checks            │
                         └────────────┬────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    │                                   │
          ┌─────────▼──────────┐             ┌─────────▼──────────┐
          │   CloudFront CDN   │             │   CloudFront CDN   │
          │  (us-east-1 Origin)│             │  (us-west-2 Origin)│
          │  + WAF + Shield    │             │  + WAF + Shield    │
          └─────────┬──────────┘             └─────────┬──────────┘
                    │                                   │
          ┌─────────▼──────────┐             ┌─────────▼──────────┐
          │ PRIMARY REGION     │  Replication │ DR REGION          │
          │ us-east-1          │ ◀──────────▶ │ us-west-2          │
          │                    │             │                    │
          │ ALB                │             │ ALB (standby)      │
          │ EC2 ASG (2-20)     │             │ EC2 ASG (2-4)      │
          │ ElastiCache Redis  │             │ ElastiCache Redis  │
          │ Aurora Primary     │             │ Aurora Read Replica │
          │                    │             │ (promoted on DR)   │
          └────────────────────┘             └────────────────────┘

          S3 (static assets) ─── CRR ──▶ S3 (us-west-2 replica)
```

---

## 3. AWS Services — Chosen and Why

### Traffic & Content Delivery

| Service | Why Chosen | Alternative Considered | Tradeoff |
|---------|-----------|----------------------|----------|
| **Route 53** | Native AWS DNS with health checks and latency routing | Third-party DNS (Cloudflare) | AWS-native = tighter integration with health checks; Cloudflare = cheaper, faster TTL changes |
| **CloudFront** | Global CDN with 450+ edge locations, WAF integration, signed URLs | Akamai, Fastly | CloudFront tighter AWS integration; Akamai better for very large enterprises with dedicated support |
| **AWS WAF** | L7 firewall — blocks OWASP top 10, rate limiting | Cloudflare WAF | WAF included with Shield Advanced; Cloudflare easier to manage but another vendor |
| **AWS Shield Advanced** | DDoS protection for flash sale events | Shield Standard (free) | Shield Advanced costs $3,000/month but provides cost protection and 24/7 DRT access |

### Compute

| Service | Why Chosen | Alternative Considered | Tradeoff |
|---------|-----------|----------------------|----------|
| **ALB** | Layer 7 routing, path-based rules, sticky sessions, health checks | NLB | NLB = ultra-low latency for TCP; ALB = HTTP-aware (chose ALB for HTTP session affinity) |
| **EC2 Auto Scaling** | Predictive + dynamic scaling for known flash sale spikes | ECS Fargate | EC2 = more control, cheaper at scale; Fargate = zero server management, better for microservices |
| **EC2 r6i.large** | Memory-optimized for PHP/Node app with session data | t3.large | r-series = better memory/CPU ratio for app servers with large working sets |

### Data Layer

| Service | Why Chosen | Alternative Considered | Tradeoff |
|---------|-----------|----------------------|----------|
| **Aurora MySQL Multi-AZ** | Managed MySQL-compatible, 6-way replication, < 30s failover | RDS MySQL Multi-AZ | Aurora failover 2-3x faster than RDS; Aurora 20% more expensive but HA included |
| **Aurora Global Database** | Sub-second replication to DR region for RPO < 1 min | RDS Read Replica cross-region | Aurora Global = < 1s replication lag; RDS cross-region replica = typically 5-60s lag |
| **ElastiCache for Redis** | Session storage, product catalog cache, cart cache | Memcached, DAX | Redis = persistent, replication, data structures; Memcached = simpler, multi-threaded; chose Redis for session durability |
| **S3 + CRR** | Static assets (images, CSS, JS) with cross-region replication | EFS | S3 = cheaper, global CDN-friendly; EFS = POSIX filesystem but overkill for static assets |

---

## 4. Scaling Strategy

### Pre-Event Scaling (Scheduled)
Flash sales are predictable. Use **scheduled scaling** to pre-warm the ASG:

```
T-30 min: Scale from 4 → 12 instances (pre-warm)
T=0:      Traffic hits, dynamic scaling active (12 → 20 if needed)
T+2h:     Scale back to steady state (4 instances)
```

### Dynamic Scaling Policies
- **Target Tracking:** ALBRequestCountPerTarget = 1,000 requests/instance
- **Step Scaling:** CPU > 70% → add 4 instances; CPU < 30% → remove 2 instances
- **Cooldown:** 180 seconds (avoid thrashing during rapid spikes)

### Cache-Aside Pattern (ElastiCache)
```
Request → App → Check Redis cache
  Cache HIT  → Return cached product data (< 1ms)
  Cache MISS → Query Aurora → Write to Redis (TTL 300s) → Return data
```

Cache hit ratio target: **> 85%** for product catalog during flash sales.

### Database Read Scaling
- 1 Aurora Primary (writes)
- 2 Aurora Read Replicas in us-east-1 (reads — product catalog, search)
- 1 Aurora Read Replica in us-west-2 (DR / regional reads)

---

## 5. Security Architecture

### Network Isolation (Defense in Depth)

```
Internet → CloudFront + WAF
         → ALB (Public Subnet, SG: 443 from CloudFront only)
         → EC2 (Private Subnet, SG: 443 from ALB SG only)
         → Aurora (Private Subnet, SG: 3306 from EC2 SG only)
         → ElastiCache (Private Subnet, SG: 6379 from EC2 SG only)
```

**Key Rule:** No security group allows `0.0.0.0/0` inbound except CloudFront's managed prefix list on the ALB.

### IAM Design (Least Privilege)

```hcl
# EC2 instances use IAM Instance Profile — zero static credentials
EC2 Role Permissions:
  - s3:GetObject on arn:aws:s3:::shopfast-assets/*
  - secretsmanager:GetSecretValue on arn:aws:secretsmanager:*:*:secret:shopfast/db/*
  - cloudwatch:PutMetricData
  - ssm:GetParameter on /shopfast/*

# NO admin access, NO IAM permissions, NO cross-account access
```

### Encryption

| Layer | Mechanism |
|-------|-----------|
| Data in transit | TLS 1.2+ enforced on ALB, CloudFront, RDS |
| RDS at rest | AES-256 via AWS KMS (customer-managed CMK) |
| S3 at rest | SSE-S3 (server-side encryption with S3-managed keys) |
| ElastiCache | In-transit TLS + at-rest encryption enabled |
| Secrets | AWS Secrets Manager (auto-rotation every 30 days for DB password) |

### PCI-DSS Compliance Decisions
- Card data **never** stored on EC2 — tokenized via Stripe (no cardholder data environment on AWS)
- VPC Flow Logs enabled, forwarded to S3 + CloudWatch for 1-year retention
- CloudTrail enabled in all regions with S3 log archive and integrity validation
- AWS Config rules: `restricted-ssh`, `rds-storage-encrypted`, `s3-bucket-public-read-prohibited`

---

## 6. High Availability & Disaster Recovery

### Failure Mode Analysis

| Failure | Detection | Response | RTO |
|---------|-----------|----------|-----|
| Single EC2 fails | ALB health check (30s) | ASG replaces instance | 3-5 min |
| Entire AZ outage | Route 53 health check | ALB shifts to surviving AZ | < 1 min |
| Aurora Primary fails | Aurora internal | Automatic failover to replica | < 30 sec |
| Full us-east-1 region fails | Route 53 health check (60s) | DNS failover to us-west-2 | 10-15 min |
| ElastiCache node fails | Redis Sentinel | Automatic replica promotion | < 60 sec |

### DR Runbook (Region Failover)
1. Route 53 health check detects primary region failure
2. DNS TTL of 60s ensures fast propagation to us-west-2 endpoint
3. Aurora Global Database secondary promoted to primary in us-west-2 (< 1 min, RPO < 1 min)
4. us-west-2 ASG scales from warm standby (2 instances) to production capacity
5. ElastiCache in us-west-2 handles cold cache (cache rebuild within 5-10 min)

### Multi-AZ vs Multi-Region Decision

> **Why not active-active multi-region?**  
> Active-active requires solving distributed write conflicts in Aurora — Aurora Global Database only supports one writer region. Active-active adds complexity: dual writes, conflict resolution, and 2x cost. For ShopFast's RPO=1min and RTO=15min, **active-passive warm standby** is the right tradeoff.

---

## 7. Cost Optimization

### Monthly Cost Estimate (us-east-1 primary)

| Service | Specification | Monthly Cost |
|---------|--------------|-------------|
| EC2 ASG (avg 6 instances, r6i.large) | On-Demand | ~$590 |
| EC2 ASG — Reserved (1yr, no upfront) | 4 baseline instances | Save ~35% = -$206 |
| Aurora MySQL (db.r6g.large, Multi-AZ) | 1 writer + 2 readers | ~$280 |
| ElastiCache Redis (cache.r6g.large) | 1 primary + 1 replica | ~$185 |
| CloudFront | 50TB/month transfer | ~$425 |
| ALB | ~10M requests/month | ~$45 |
| S3 + CRR | 500GB + replication | ~$30 |
| Route 53 | Hosted zone + health checks | ~$12 |
| WAF | 10M requests | ~$30 |
| Secrets Manager | 5 secrets | ~$2 |
| **Total (primary region)** | | **~$1,393/month** |
| DR region (warm standby) | ~40% of primary cost | **~$557/month** |
| **Grand Total** | | **~$1,950/month** |

### Cost Optimization Decisions

1. **Reserved Instances for baseline:** 4 r6i.large on 1-year RI = 35% savings vs On-Demand
2. **Spot Instances for burst:** Flash sale burst capacity (above 6 instances) uses Spot with On-Demand fallback — saves 70% on burst compute
3. **CloudFront caching:** 85% cache hit ratio means 85% less traffic reaches the origin (saves EC2 and data transfer costs)
4. **S3 Intelligent Tiering:** Product images auto-tier from S3 Standard → Infrequent Access after 30 days
5. **Aurora Serverless v2 consideration:** For non-flash-sale hours, Aurora Serverless v2 would scale to 0.5 ACUs — but chosen fixed instance for predictable pricing

---

## 8. CAP Theorem Considerations

ShopFast prioritizes **Availability over Consistency** for the product catalog and cart:

- **Product catalog (Redis + Aurora):** Cache may serve slightly stale data (300s TTL) — acceptable. Consistency is eventual.
- **Inventory count (Aurora Primary only):** Consistency required. All inventory decrements go to the primary writer. Cannot serve stale inventory counts (overselling is a critical failure).
- **Shopping cart (Redis):** Available and partition-tolerant. Cart data can be slightly inconsistent across sessions.

> **Interview Answer:** "I chose AP for catalog reads and CP for inventory writes — because overselling is a business-critical failure, but showing a slightly stale product price for 5 minutes is acceptable."

---

## 9. Architecture Diagram (GitHub)

For your GitHub `diagrams/` folder, create this using [draw.io](https://draw.io) or [Excalidraw](https://excalidraw.com):

**Diagram Layout:**
- Top layer: Users, Route 53, CloudFront + WAF
- Middle layer: Two VPC boxes side-by-side (us-east-1 and us-west-2) with AZ subdivisions
- Inside each VPC: Public subnet (ALB), Private App subnet (EC2 ASG), Private Data subnet (Aurora, ElastiCache)
- Arrows: Replication between Aurora Global DB, S3 CRR
- Color coding: Green = public, Yellow = private app, Red = private data

---

## 10. Terraform Structure

```
terraform/
├── variables.tf       # All input variables
├── vpc.tf             # VPC, subnets, IGW, NAT Gateway, route tables
├── security.tf        # Security groups (ALB, EC2, RDS, ElastiCache)
├── compute.tf         # Launch template, ASG, scaling policies
├── database.tf        # Aurora cluster, parameter group, subnet group
├── cache.tf           # ElastiCache cluster, subnet group
├── cdn.tf             # CloudFront distribution, WAF, S3 origin
├── dns.tf             # Route 53 records, health checks, failover routing
├── iam.tf             # EC2 instance role, S3 policies, Secrets Manager access
├── monitoring.tf      # CloudWatch alarms, dashboards, SNS topics
└── outputs.tf         # ALB DNS, CloudFront domain, Aurora endpoint
```

---

## 11. Interview Talking Points

**Q: Why Aurora over standard RDS MySQL?**  
Aurora replicates across 6 storage nodes in 3 AZs automatically — you get 99.99% storage durability without managing replicas. Failover is 30 seconds vs RDS's 60-120 seconds. The cost premium (20%) is worth it for our 99.99% SLA requirement.

**Q: Why not use ECS Fargate instead of EC2 ASG?**  
For a stateful PHP/Node monolith with session state, EC2 gives us more control over instance type, OS tuning, and network placement. If we were building microservices from scratch, I'd choose Fargate for zero server management. We'd migrate to Fargate as part of a future modernization phase.

**Q: How do you handle the cold cache problem during failover?**  
After a region failover, ElastiCache in us-west-2 starts cold. We mitigate this by: (1) keeping the ASG warm in us-west-2 so EC2s can start accepting traffic, (2) Aurora Global DB has current data — cache rebuilds within 10 minutes as traffic comes through, and (3) CloudFront edge caches remain warm, so the CDN absorbs initial traffic while the origin cache rebuilds.

---

## Setup Instructions

```bash
# Prerequisites: AWS CLI configured, Terraform >= 1.5

cd terraform/

# Initialize
terraform init

# Review the plan (dry run)
terraform plan -var-file="production.tfvars"

# Deploy primary region
terraform apply -var-file="production.tfvars" -target=module.primary

# Deploy DR region
terraform apply -var-file="production.tfvars" -target=module.dr

# Store DB credentials in Secrets Manager
aws secretsmanager create-secret \
  --name shopfast/db/master \
  --secret-string '{"username":"admin","password":"CHANGE_ME"}' \
  --region us-east-1
```

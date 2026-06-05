# AWS Solutions Architect — Complete Mastery Guide

**Author:** Vanessa Awo | Built for entry-level AWS SA interview preparation

This folder contains everything you need to go from understanding the projects to confidently explaining them in any interview. Work through it in order.

---

## How to Use This Guide

```
Week 1-2 → Read all Concepts files (understand the building blocks)
Week 3-4 → Work through Practice files hands-on (build muscle memory)
Week 5-6 → Drill Interview files daily (internalize the language)
Week 7+  → Mock interviews using the Master Question Bank
```

---

## Study Path

### Step 1 — Learn the Core Concepts

Read these before touching any project. Every project uses these building blocks.

| File | What You'll Learn | Time |
|------|------------------|------|
| [VPC & Networking](./concepts/01-vpc-and-networking.md) | Subnets, routing, security groups, NACLs, NAT | 45 min |
| [Compute: EC2, ASG, ALB](./concepts/02-compute-ec2-asg-alb.md) | Instances, auto scaling, load balancing | 45 min |
| [Databases: Aurora & RDS](./concepts/03-databases-aurora-rds.md) | Aurora vs RDS, read replicas, failover, backups | 40 min |
| [Caching: ElastiCache Redis](./concepts/04-caching-elasticache.md) | Cache patterns, eviction, cluster mode | 30 min |
| [Serverless: Lambda & SQS](./concepts/05-serverless-lambda-sqs.md) | Lambda triggers, SQS patterns, DLQ, EventBridge | 45 min |
| [Storage: S3 & CloudFront](./concepts/06-storage-s3-cloudfront.md) | S3 storage classes, CloudFront, OAC, signed URLs | 40 min |
| [Security: IAM, KMS, WAF](./concepts/07-security-iam-kms-waf.md) | IAM policies, KMS encryption, WAF rules | 45 min |
| [Messaging: Kinesis & SNS](./concepts/08-messaging-kinesis-sns.md) | Kinesis streams, SNS fan-out, ordering guarantees | 30 min |

### Step 2 — Practice Hands-On (CLI + Console)

Each file walks you through building the project step by step using the AWS Console and CLI. No Terraform — just you and AWS.

| File | Project | Services You'll Touch |
|------|---------|----------------------|
| [Project 1 Practice](./practice/project-1-hands-on.md) | E-Commerce Platform | VPC, EC2, Aurora, ElastiCache, CloudFront, WAF |
| [Project 2 Practice](./practice/project-2-hands-on.md) | SaaS Multi-Tenant | Lambda, DynamoDB, API Gateway, Cognito, EventBridge |
| [Project 3 Practice](./practice/project-3-hands-on.md) | FinTech Data Lake | S3, Glue, Athena, Lake Formation, Macie |
| [Project 4 Practice](./practice/project-4-hands-on.md) | Media Streaming | CloudFront, S3, MediaConvert, signed URLs |
| [Project 5 Practice](./practice/project-5-hands-on.md) | Ride-Sharing | WebSocket API, Kinesis, OpenSearch, Redis |
| [Project 6 Practice](./practice/project-6-hands-on.md) | Image Platform | Full stack — all services combined |

### Step 3 — Interview Prep Per Project

For each project, master: the business problem, the architecture decision, the tradeoff, and the failure mode.

| File | Project | Key Interview Themes |
|------|---------|---------------------|
| [Project 1 Interview](./interview/project-1-ecommerce-prep.md) | E-Commerce | Multi-region, DR, session management |
| [Project 2 Interview](./interview/project-2-saas-prep.md) | SaaS | Multi-tenancy, isolation, serverless costs |
| [Project 3 Interview](./interview/project-3-fintech-prep.md) | FinTech | Compliance, data governance, lake formation |
| [Project 4 Interview](./interview/project-4-media-prep.md) | Media | CDN, signed URLs, adaptive bitrate |
| [Project 5 Interview](./interview/project-5-ridesharing-prep.md) | Ride-Sharing | Real-time systems, geospatial, WebSockets |
| [Project 6 Interview](./interview/project-6-pixelvault-prep.md) | Image Platform | Scale, fan-out, viral traffic, hot partitions |

### Step 4 — Master Question Bank

[100+ interview questions](./interview/master-question-bank.md) organized by domain. Use this for daily drilling.

---

## The Interviewer's Mental Model

When an interviewer asks "Walk me through your architecture," they are scoring you on:

1. **Business context** — Do you understand WHY the system needs to be built this way?
2. **Service selection** — Do you know WHAT each AWS service does and WHY you chose it?
3. **Tradeoff awareness** — Do you know what you GAVE UP by making that choice?
4. **Failure thinking** — Do you know what breaks FIRST and how to recover?
5. **Cost awareness** — Do you know roughly what this costs and how to optimize it?

Every answer in this guide is structured to hit all five points.

---

## The One-Sentence Framework

For any architecture question, use this structure:

> "We needed [business requirement], so we chose [AWS service] because [specific capability], even though [tradeoff], which we mitigated by [solution]."

**Example:**
> "We needed sub-millisecond feed reads for 10 million users, so we chose ElastiCache Redis because it serves pre-computed results from memory, even though it adds operational complexity for cluster management, which we mitigated by using ElastiCache cluster mode with automatic failover and the LRU eviction policy so Redis never becomes a hard dependency."

---

## Quick Reference — Service Cheat Sheet

| When you need... | Use this | Not this | Why |
|-----------------|----------|----------|-----|
| Sub-ms reads | ElastiCache Redis | DynamoDB DAX | Redis is more flexible (geospatial, pub/sub, sorted sets) |
| Relational + HA | Aurora MySQL | RDS MySQL | Aurora: 6-way replication, 15 replicas, 5x throughput |
| Ordered event stream | Kinesis | SQS Standard | Kinesis: per-shard ordering; SQS: at-least-once, no order |
| At-least-once delivery | SQS | SNS alone | SQS persists messages; SNS is fire-and-forget |
| Fan-out to many | SNS → SQS | SQS alone | SNS broadcasts; SQS queues for each subscriber |
| Global image serving | CloudFront + S3 | EC2 | CloudFront: 450+ edge locations; EC2: one region |
| WebSocket API | API GW WebSocket | ALB | API GW manages connection state; ALB is stateless |
| JWT auth + user mgmt | Cognito | Custom auth | Cognito: managed MFA, TOTP, social IdP; no servers |
| Encryption key mgmt | KMS CMK | SSE-S3 | CMK: per-service keys, audit trail, cross-account |
| Secrets rotation | Secrets Manager | Parameter Store | SM: auto-rotation Lambda; PS: no built-in rotation |
| OWASP protection | WAF managed rules | Custom rules | AWS-managed rules: updated by AWS security team |
| Infrastructure audit | CloudTrail | VPC Flow Logs | CT: API calls; VPC FL: network traffic |

# Project 6: PixelVault — Global Image Sharing Platform

> **Role Focus:** AWS Solutions Architect
> **Scenario:** Social Media / Consumer Platform
> **Scale:** 10 Million Monthly Active Users
> **Interview Depth:** Full end-to-end architecture explanation

---

## Table of Contents

1. [Business Scenario](#1-business-scenario)
2. [Architecture Overview](#2-architecture-overview)
3. [Detailed Architecture Flow](#3-detailed-architecture-flow)
4. [High Availability Design](#4-high-availability-design)
5. [Scalability Strategy](#5-scalability-strategy)
6. [Security Architecture](#6-security-architecture)
7. [Cost Optimization](#7-cost-optimization)
8. [Failure Scenarios](#8-failure-scenarios)
9. [Architecture Diagram](#9-architecture-diagram)
10. [Repository Structure](#10-repository-structure)

---

## 1. Business Scenario

### The Company

**PixelVault** is a consumer social media platform where users upload, organize, and share high-resolution photos and short video clips — similar to Instagram and Pinterest combined. Users can follow creators, explore trending content, and save collections to personal boards.

The platform has grown from 500K to **10 million monthly active users** over 18 months and is now preparing to expand from the US into Europe and Southeast Asia.

### Scale and Traffic Requirements

| Metric | Current | 12-Month Target |
|--------|---------|-----------------|
| Monthly Active Users | 10M | 40M |
| Daily Active Users | 500K | 2M |
| Peak Concurrent Users | 50,000 | 200,000 |
| Image Uploads / Day | 2,000,000 | 8,000,000 |
| Image Views / Day | 20,000,000 | 80,000,000 |
| Avg Image Size (raw) | 4MB | 4MB |
| Avg Image Size (served) | 120KB (WebP, compressed) | 120KB |
| Video Clips / Day | 100,000 | 500,000 |

### Traffic Patterns

```
Normal hours (9am-6pm EST):    ~5,000 req/sec
Evening peak (7pm-10pm EST):   ~25,000 req/sec
Viral event (trending moment): ~100,000 req/sec (10x normal)
Overnight (2am-6am EST):       ~500 req/sec
```

**Viral spikes are unpredictable.** When a celebrity posts from the platform, traffic can jump 20x within 60 seconds. The architecture must scale automatically without human intervention.

### Latency Requirements

| Operation | Target P50 | Target P99 |
|-----------|-----------|-----------|
| Feed load (cached) | < 50ms | < 200ms |
| Image display (CDN hit) | < 30ms | < 100ms |
| Image upload acknowledgment | < 500ms | < 2,000ms |
| Search results | < 200ms | < 800ms |
| Profile load | < 100ms | < 400ms |

### Availability Requirements

- **API availability:** 99.99% (< 52 minutes downtime/year)
- **Media delivery (CDN):** 99.999% (CloudFront SLA)
- **Data durability (images):** 99.999999999% (S3 11 nines)
- **RTO (recovery time objective):** < 15 minutes
- **RPO (recovery point objective):** < 1 minute

---

## 2. Architecture Overview

### Full Architecture Diagram (Text)

```
                          GLOBAL USERS
                         (US, EU, APAC)
                               │
                    ┌──────────▼──────────┐
                    │     Route 53        │
                    │  Latency-based      │
                    │  routing + health   │
                    │  checks             │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  CloudFront (CDN)   │
                    │  450+ Edge PoPs     │
                    │  + AWS WAF          │
                    │  + Shield Standard  │
                    └──────┬──────┬───────┘
                           │      │
              ┌────────────┘      └───────────────┐
              │                                   │
    ┌─────────▼──────┐                  ┌─────────▼──────┐
    │  S3 Origin     │                  │  ALB Origin    │
    │  (Images/Video │                  │  (API calls)   │
    │   static files)│                  │                │
    └────────────────┘                  └────────┬───────┘
                                                 │
                              ┌──────────────────┤
                              │    VPC           │
                              │                  │
                    ┌─────────▼──────────┐       │
                    │  EC2 Auto Scaling  │       │
                    │  (API Servers)     │       │
                    │  Private Subnets   │       │
                    │  2-50 instances    │       │
                    └──┬──────────┬──────┘       │
                       │          │              │
              ┌────────▼──┐  ┌───▼──────────┐   │
              │ElastiCache│  │   Lambda     │   │
              │  Redis    │  │  Workers     │   │
              │(Feed cache│  │(image resize,│   │
              │ sessions) │  │ thumbnail)   │   │
              └───────────┘  └──────┬───────┘   │
                                    │           │
              ┌─────────────────────┤           │
              │                     │           │
    ┌─────────▼──────┐   ┌──────────▼──┐        │
    │   DynamoDB     │   │   Amazon    │        │
    │  (posts,       │   │   SQS       │        │
    │   likes,       │   │ (processing │        │
    │   follows,     │   │  queue)     │        │
    │   feed)        │   └─────────────┘        │
    └────────────────┘                          │
    ┌────────────────┐                          │
    │  Aurora MySQL  │                          │
    │  (users,       │                          │
    │   accounts,    │                          │
    │   billing)     │                          │
    └────────────────┘                          │
                                                │
              CloudWatch Monitoring (all tiers) │
```

### AWS Services Used and Why

#### Traffic & Delivery Layer

| Service | Purpose | Why Chosen |
|---------|---------|-----------|
| **Route 53** | DNS with latency-based routing | Routes US users to us-east-1, EU users to eu-west-1 — reduces round-trip by 100-150ms. Health checks automatically remove a failing region from DNS. |
| **CloudFront** | Global CDN for all content | 450+ edge PoPs cache images globally. A photo uploaded in New York is served in Tokyo at < 30ms from the edge — without hitting the origin. Handles 80M image views/day without hitting S3 directly. |
| **AWS WAF** | Web Application Firewall | Blocks OWASP Top 10 attacks, rate-limits scrapers (bots that steal content), and enforces geographic restrictions. Protects against image scraping, account takeover, and spam uploads. |

#### Compute Layer

| Service | Purpose | Why Chosen |
|---------|---------|-----------|
| **ALB** | Layer 7 load balancing | Routes `/api/*` to EC2, `/media/*` to CloudFront S3 origin. Health checks remove unhealthy instances in 30 seconds. Supports WebSocket for real-time notifications. |
| **EC2 Auto Scaling** | API server fleet | Target tracking on CPU (60%) and ALBRequestCountPerTarget (1,000). Scales 2 → 50 instances during viral events. Uses m6i.xlarge (4 vCPU, 16GB) — balanced for Node.js/Python API workloads. |
| **Lambda** | Image processing workers | Triggered by SQS. Resizes uploaded images to 5 renditions (thumbnail, small, medium, large, original). Serverless = zero cost when no uploads happening. Handles burst of 1,000 concurrent image jobs automatically. |
| **API Gateway** | Mobile API endpoint | Used for the mobile app's REST API with per-client rate limiting. Handles authentication with Cognito JWT. Separate from the web API (ALB) for better mobile telemetry. |

#### Data Layer

| Service | Purpose | Why Chosen |
|---------|---------|-----------|
| **DynamoDB** | Posts, likes, follows, user feeds | Single-digit millisecond reads at any scale. PAY_PER_REQUEST handles viral traffic without pre-provisioning. Designed for the access patterns that matter: "get user's feed", "get post's likes", "does user A follow user B?" |
| **Aurora MySQL (Multi-AZ)** | User accounts, authentication, billing | Relational data requiring ACID transactions. User registration, login, subscription billing cannot have eventual consistency. Aurora failover in < 30 seconds. |
| **ElastiCache Redis** | Feed cache, sessions, trending | Pre-computed user feeds cached for 60 seconds. Session tokens cached for auth. Trending hashtags cached for 5 minutes. Reduces DynamoDB reads by 90% during peak hours. |
| **S3** | Image and video storage | 11 nines durability. Infinite scale. Intelligent Tiering moves cold content to cheaper storage. Origin for CloudFront. Versioning prevents accidental deletion. |

#### Async Processing

| Service | Purpose | Why Chosen |
|---------|---------|-----------|
| **SQS** | Image processing job queue | Decouples upload from processing. A viral post generating 10,000 re-shares doesn't overwhelm Lambda — SQS buffers the jobs and Lambda processes at its own pace. DLQ captures failed jobs. |
| **Lambda** | Async image processing | Auto-scales to 1,000 concurrent workers. Resizes images, generates thumbnails, runs content moderation (Rekognition), sends notifications. Costs $0 between processing jobs. |

#### Observability

| Service | Purpose | Why Chosen |
|---------|---------|-----------|
| **CloudWatch** | Metrics, logs, alarms | Single pane of glass for all AWS resources. Alarm on p99 latency > 500ms, DynamoDB throttling, SQS DLQ depth, EC2 CPU > 70%. Dashboard visible to on-call engineer. |

---

## 3. Detailed Architecture Flow

### Flow 1: User Views Their Feed (Read Path — Most Common)

```
Step 1: User opens app
        → DNS lookup: Route 53 returns us-east-1 ALB (lowest latency)

Step 2: Request reaches CloudFront edge (Atlanta PoP for Georgia user)
        → CloudFront checks: is /api/v1/feed/{user_id} cached?
        → API responses: Cache-Control: public, max-age=30
        → Cache HIT → returns in < 30ms, never hits origin

Step 3: Cache MISS → CloudFront forwards to ALB
        → WAF inspects request (rate limit, OWASP rules, bot check)
        → ALB routes to healthiest EC2 instance in private subnet

Step 4: EC2 API server receives request
        → Validates JWT (Cognito) — verifies signature locally (no network call)
        → Checks Redis: "feed:{user_id}" key exists?
        → Cache HIT (60s TTL): return feed JSON in < 10ms
        → Cache MISS: query DynamoDB for feed events

Step 5: DynamoDB query (on cache miss)
        → PK = "USER#{user_id}", SK begins_with("FEED#")
        → Returns 20 post IDs + metadata
        → EC2 writes result to Redis (60s TTL)
        → Returns feed to user

Step 6: App renders image thumbnails
        → Each thumbnail URL points to CloudFront (cdn.pixelvault.com)
        → CloudFront edge serves from cache (TTL: 7 days for images)
        → Images never hit S3 origin if cached

Total time for cached feed: ~35ms
Total time for uncached feed: ~120ms
```

### Flow 2: User Uploads an Image (Write Path)

```
Step 1: Client requests a pre-signed S3 upload URL
        → POST /api/v1/uploads/presign
        → EC2 API server generates S3 pre-signed URL (valid 15 minutes)
        → Returns: { "upload_url": "https://s3.amazonaws.com/...", "upload_id": "u_abc123" }

Step 2: Client uploads image DIRECTLY to S3 (bypasses EC2 fleet)
        → PUT to pre-signed URL (up to 500MB, multipart for large files)
        → S3 receives 4MB raw image
        → S3 triggers EventBridge notification: "ObjectCreated"
        → EC2 fleet never handles image bytes — eliminates bandwidth bottleneck

Step 3: Lambda (triggered by S3 event) puts job on SQS
        → Message: { "upload_id": "u_abc123", "s3_key": "raw/2024/01/abc123.jpg", "user_id": "u_456" }
        → API immediately responds to client: "Upload received, processing..."
        → Client sees "Processing" state — decoupled from actual work

Step 4: Lambda Worker polls SQS (event source mapping)
        → Reads raw image from S3
        → Runs through PIL/Sharp:
            thumbnail:  150x150  (for feed grid)
            small:      400x400  (for feed detail)
            medium:     800x800  (for full view)
            large:      1200x1200 (for desktop)
            webp:       convert all to WebP (60% smaller than JPEG)
        → Writes 5 renditions back to S3: processed/{upload_id}/thumb.webp, etc.
        → Sends to Rekognition: content moderation check (violence, nudity)

Step 5: Lambda writes post metadata to DynamoDB
        → PK = "POST#{post_id}"
        → SK = "META"
        → Attributes: user_id, caption, tags, s3_paths, status=published, created_at
        → Writes to feed table: PK = "USER#{follower_id}", SK = "FEED#{timestamp}#{post_id}"
        → This fan-out writes notify all followers' feeds

Step 6: Lambda invalidates CloudFront cache
        → aws cloudfront create-invalidation --paths "/api/v1/feed/*"
        → Followers' next feed load gets fresh data

Step 7: Lambda sends push notification via SNS → Pinpoint → Mobile
        → "Your photo has been posted!"

Total upload-to-visible time: ~15-30 seconds for processing
Total API response time: ~300ms (returns before processing completes)
```

### Flow 3: Background Feed Fan-Out (Viral Post)

```
Problem: A creator with 2,000,000 followers posts a photo.
         Writing to 2M feed records instantly = DynamoDB write spike.

Solution: Fan-out via SQS with batched writes

Step 1: Upload completes → SQS "fan-out" message published
        → Message: { "post_id": "p_123", "creator_id": "u_456", "created_at": "..." }

Step 2: Lambda Fan-Out Worker reads follower list from DynamoDB
        → Query: PK = "CREATOR#u_456", SK begins_with("FOLLOWER#")
        → Pages through 2,000,000 follower records in batches of 1,000

Step 3: For each batch of 1,000 followers:
        → Lambda writes 1,000 feed records to DynamoDB (BatchWriteItem)
        → DynamoDB handles ~5,000 writes/sec — 2M writes takes ~400 seconds
        → Acceptable: follower sees post within 7 minutes (push notification is instant)

Step 4: Redis cache invalidation
        → For the 10,000 most-followed creators: pre-compute and cache feed
        → For regular creators: lazy cache rebuild on next request
```

### Flow 4: Database Read and Write Separation

```
WRITE PATH:
  EC2 API Server
    → Aurora Writer (ACID transactions for user accounts)
    → DynamoDB (post metadata, likes, follows — eventually consistent writes OK)
    → Redis (write-through cache for frequently read data)

READ PATH:
  EC2 API Server
    → Redis (L1 cache — check first, 60s-7day TTL)
    → DynamoDB (L2 — single-digit ms, eventually consistent reads for feeds)
    → Aurora Reader Replica (L3 — user profile reads, search)
    → Never hits Aurora Writer for reads (prevents write bottleneck)

Cache hierarchy:
  CloudFront edge   → TTL 7 days   (images, static assets)
  Redis             → TTL 60s-5min (feeds, trending, sessions)
  DynamoDB          → No cache (metadata reads direct)
  Aurora Reader     → Connection pooled, max 50 connections
```

---

## 4. High Availability Design

### Multi-AZ Architecture

```
us-east-1 (Primary Region)
│
├── AZ: us-east-1a
│   ├── EC2 ASG instances (min 1)
│   ├── Aurora Writer node
│   ├── ElastiCache Primary
│   └── Private subnets (app tier)
│
├── AZ: us-east-1b
│   ├── EC2 ASG instances (min 1)
│   ├── Aurora Reader Replica
│   ├── ElastiCache Replica
│   └── Private subnets (app tier)
│
├── AZ: us-east-1c
│   ├── EC2 ASG instances (min 1)
│   ├── Aurora Reader Replica
│   └── Private subnets (app tier)
│
├── Public Subnets (all 3 AZs)
│   ├── ALB nodes
│   └── NAT Gateways
│
└── Global
    ├── S3 (11 nines durability, replicated within region)
    ├── DynamoDB (Multi-AZ by default, Global Tables for multi-region)
    └── CloudFront (450+ PoPs, automatic failover between PoPs)
```

### Failure Response Matrix

| Component Fails | Detection Time | Automatic Response | RTO |
|----------------|---------------|-------------------|-----|
| Single EC2 instance | ALB health check: 30s | ASG replaces instance, ALB stops routing | < 3 min |
| Entire AZ (1c fails) | ALB health check: 30s | ALB routes to 1a and 1b instances only | < 1 min |
| Aurora Primary node | Aurora monitoring: 10s | Automatic failover to Reader in 1b | < 30s |
| ElastiCache Primary | Redis Sentinel: 5s | Read Replica promoted to Primary | < 60s |
| NAT Gateway (1c) | Route table: immediate | Private instances use NAT in 1a or 1b | < 1 min |
| Full us-east-1 region | Route 53 health check: 60s | DNS fails over to eu-west-1 | < 15 min |

### ALB Health Check Configuration

```hcl
health_check {
  path                = "/health"          # Returns 200 if app is healthy
  interval            = 30                 # Check every 30 seconds
  healthy_threshold   = 2                  # 2 consecutive successes = healthy
  unhealthy_threshold = 3                  # 3 consecutive failures = unhealthy
  timeout             = 5                  # Fail if no response in 5s
  matcher             = "200"
}
```

The `/health` endpoint checks:
1. Redis connection: can it read/write?
2. DynamoDB: can it perform a GetItem?
3. App memory: is heap usage < 90%?

If any check fails, the instance is marked unhealthy and removed from ALB in 90 seconds (3 checks × 30 seconds).

### Multi-Region Disaster Recovery

```
us-east-1 (Primary — Active)
│ Aurora Global Database primary writer
│ DynamoDB Global Tables writer
│ S3 Cross-Region Replication → eu-west-1
│
eu-west-1 (DR — Warm Standby)
│ Aurora Global Database secondary reader
│   → Promote to writer in < 1 minute during DR
│ DynamoDB Global Tables writer (can accept writes immediately)
│ S3 replica bucket (1-15 min replication lag)
│ EC2 ASG with min=2 (warm standby instances running)
│
Route 53 Failover:
  Primary: api.pixelvault.com → us-east-1 ALB
  Secondary: api.pixelvault.com → eu-west-1 ALB
  Failover trigger: health check fails 3 consecutive times (60-180 seconds)
```

---

## 5. Scalability Strategy

### Auto Scaling — Handling Viral Events

#### The Viral Event Problem
A celebrity with 10M followers posts from PixelVault. Within 60 seconds, traffic spikes from 5,000 req/sec to 100,000 req/sec. Cold boot of an EC2 instance takes 3-5 minutes. Without pre-warming, users see errors for the first 5 minutes of the event.

#### Solution: Predictive + Reactive Scaling

```
Layer 1 — CloudFront (immediate, no scaling needed)
  90% of requests are image views → served from CloudFront edge cache
  CloudFront handles 100K additional image requests/sec with zero configuration
  Cost: $0 additional (already caching)

Layer 2 — Redis (immediate)
  Pre-computed feeds for high-follower accounts
  A user loading the celebrity's profile hits Redis, not DynamoDB
  Cache handles the read spike for the first 60 seconds

Layer 3 — EC2 Auto Scaling (3-5 minutes)
  Target tracking: ALBRequestCountPerTarget = 1,000
  At 100K req/sec with 5K going to origin = 5 additional EC2 instances needed
  ASG detects target exceeded → launches instances → takes 3-5 min

Layer 4 — Lambda (immediate, handles burst)
  Image processing Lambda: 0 → 1,000 concurrent in seconds
  No waiting for EC2 boot

Layer 5 — DynamoDB (immediate)
  PAY_PER_REQUEST mode: no capacity planning
  Handles 100,000 reads/sec without any configuration change
```

#### Scheduled Scaling for Known Events

```hcl
# Pre-warm for Super Bowl halftime show (known spike):
resource "aws_autoscaling_schedule" "superbowl_prescale" {
  scheduled_action_name  = "superbowl-prescale"
  autoscaling_group_name = aws_autoscaling_group.api.name
  min_size               = 20
  max_size               = 50
  desired_capacity       = 30
  start_time             = "2025-02-09T23:00:00Z"  # 30 min before halftime
}
```

### DynamoDB Partition Design

#### Access Pattern Analysis (Critical for Partition Key Design)

```
Access Pattern 1: Get post by ID
  PK = "POST#{post_id}"  SK = "META"
  → One partition per post — uniform distribution ✓

Access Pattern 2: Get user's feed (20 most recent posts from followed creators)
  PK = "USER#{user_id}"  SK = "FEED#{timestamp}#{post_id}"
  → One partition per user — 10M partitions, evenly distributed ✓

Access Pattern 3: Get post likes count (high cardinality)
  PK = "POST#{post_id}"  SK = "LIKE#{user_id}"
  → One hot partition per popular post = PROBLEM ✗

HOT PARTITION SOLUTION — Counter sharding:
  Instead of: PK = "POST#{post_id}" SK = "LIKES_TOTAL"
  Use: PK = "POST#{post_id}#SHARD#{random 0-9}" SK = "LIKES"
  → 10 shards per post. Read all 10, sum the values.
  → Hot post gets 10x throughput, spread across 10 partitions ✓
```

#### GSI Design for Trending Content

```
Table: pixelvault-posts
  PK = "POST#{post_id}"     SK = "META"

GSI1: trending-index
  GSI1PK = "DATE#{YYYY-MM-DD}"    GSI1SK = "{like_count}#{post_id}"
  → Query: "top posts from today, sorted by likes"
  → Supports trending page without scanning full table

GSI2: user-posts-index
  GSI2PK = "USER#{user_id}"       GSI2SK = "{created_at}#{post_id}"
  → Query: "all posts by user X, newest first"
  → Supports user profile page
```

### CloudFront Cache Strategy

```
Content Type          TTL         Cache Key           Why
─────────────────────────────────────────────────────────────────────
Image thumbnails      7 days      URL path            Immutable — new upload = new URL
Image originals       30 days     URL path            Never changes once uploaded
User profile pics     1 hour      URL + user_id       User can update profile picture
API: user feed        30 seconds  URL + Authorization Shows fresh content quickly
API: post detail      5 minutes   URL path            Likes count updates eventually
API: trending         60 seconds  URL path            Trending refreshes every minute
Static (JS/CSS)       1 year      URL + file hash     Hash changes on deploy
```

### SQS Queue Buffering

```
Upload surge scenario: 1,000 concurrent photo uploads in 10 seconds
  → 1,000 SQS messages published immediately
  → Lambda concurrency limit: 100 workers active simultaneously
  → Each worker processes 1 image in ~8 seconds
  → Queue depth at peak: 900 messages
  → All processed within 90 seconds
  → No upload failures — SQS holds messages for 24 hours

Without SQS (direct Lambda invocation):
  → 1,000 concurrent Lambda cold starts
  → Lambda throttle at concurrency limit → errors
  → Lost jobs, failed uploads
```

---

## 6. Security Architecture

### VPC Design

```
PixelVault VPC (10.0.0.0/16)
│
├── Public Subnets (10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24)
│   ├── ALB (receives traffic from CloudFront only)
│   ├── NAT Gateways (outbound for private subnets)
│   └── Bastion Host (SSH access via AWS SSM only — no port 22 exposed)
│
├── Private App Subnets (10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24)
│   ├── EC2 ASG instances
│   └── Lambda (VPC-attached for Redis/Aurora access)
│
└── Private Data Subnets (10.0.20.0/24, 10.0.21.0/24, 10.0.22.0/24)
    ├── Aurora MySQL cluster
    ├── ElastiCache Redis cluster
    └── NO internet access (no NAT route)
```

### Security Group Chain (Zero-Trust Network)

```
Internet → CloudFront only (enforced by CloudFront managed prefix list)
         → ALB SG: 443 from CloudFront prefix list only
         → EC2 SG: 80 from ALB SG only (EC2 never receives direct internet)
         → Aurora SG: 3306 from EC2 SG only
         → Redis SG: 6379 from EC2 SG only
         → Lambda SG: same as EC2 SG (shares access to data layer)

Principle: each layer only accepts traffic from the layer above it.
           No security group allows 0.0.0.0/0 except CloudFront → ALB.
```

### IAM Design — Least Privilege Per Component

```
EC2 API Server Role:
  ✓ s3:GetObject on pixelvault-images/* (read images for pre-sign)
  ✓ s3:GeneratePresignedPost (generate upload URLs)
  ✓ dynamodb:GetItem, Query, PutItem, UpdateItem on posts table
  ✓ elasticache: (accessed via VPC, Redis AUTH token from Secrets Manager)
  ✓ secretsmanager:GetSecretValue on /pixelvault/db/* only
  ✗ NO s3:DeleteObject (cannot delete images)
  ✗ NO dynamodb:DeleteTable (cannot destroy data)
  ✗ NO iam:* (cannot modify permissions)

Lambda Processing Role:
  ✓ s3:GetObject on pixelvault-raw/* (read uploads)
  ✓ s3:PutObject on pixelvault-processed/* (write renditions)
  ✓ dynamodb:PutItem on posts table (write metadata)
  ✓ sqs:ReceiveMessage, DeleteMessage on processing queue
  ✓ rekognition:DetectModerationLabels (content moderation)
  ✗ NO access to Aurora (Lambda doesn't need user account data)
  ✗ NO access to Redis (Lambda is stateless)

CloudFront to S3:
  ✓ Origin Access Control (OAC) — CloudFront uses IAM-signed requests
  ✗ S3 bucket has NO public access (bucket policy denies all except CloudFront)
```

### WAF Rules

```
Rule 1: AWSManagedRulesCommonRuleSet (priority 1)
  Blocks: XSS, SQL injection, command injection, path traversal
  Action: Block

Rule 2: AWSManagedRulesKnownBadInputsRuleSet (priority 2)
  Blocks: Log4Shell, Spring4Shell, known exploit payloads
  Action: Block

Rule 3: Rate limiting per IP (priority 3)
  Threshold: 500 requests per 5 minutes per IP
  Action: Block (prevents scraping, brute force)

Rule 4: Geo blocking (priority 4)
  Block: Countries where PixelVault has no legal right to operate
  Action: Block with custom 403 response

Rule 5: Bot Management (priority 5)
  Challenge: User agents that match known bot signatures
  Action: CAPTCHA challenge (allows good bots like Google, blocks scrapers)

Rule 6: Image upload size validation (priority 6)
  Block: Requests > 500MB to upload endpoint (prevents storage abuse)
  Action: Block
```

### Encryption

| Data | At Rest | In Transit |
|------|---------|-----------|
| S3 images | SSE-S3 (AES-256) | TLS 1.2+ (CloudFront) |
| Aurora (user data) | KMS CMK (customer-managed) | TLS 1.2 enforced |
| DynamoDB | KMS CMK | TLS 1.2 enforced (AWS SDK) |
| ElastiCache | Encryption at rest enabled | TLS + AUTH token |
| SQS messages | SSE-SQS (KMS) | TLS in transit |
| Secrets (DB passwords) | AWS Secrets Manager (KMS) | IAM-controlled access |
| CloudFront ↔ Origin | TLS 1.2+ (HTTPS-only origin) | Certificate pinning |

### S3 Security

```
Bucket: pixelvault-raw-uploads
  Public access: BLOCKED (all 4 settings)
  Bucket policy: allows only EC2 role to PutObject (pre-signed URL bypasses this)
  Versioning: ENABLED (accidental delete protection)
  MFA Delete: ENABLED (malicious delete protection)
  Access logs: S3 server access logging to audit bucket

Bucket: pixelvault-processed-images
  Public access: BLOCKED
  CloudFront OAC: only access mechanism
  Lifecycle: move to STANDARD_IA after 90 days, GLACIER after 365 days
  CRR: cross-region replication to eu-west-1 (for DR + EU users)
```

---

## 7. Cost Optimization

### Monthly Cost Estimate (10M MAU)

| Service | Specification | Monthly Cost |
|---------|--------------|-------------|
| EC2 Auto Scaling | avg 8× m6i.xlarge | ~$1,120 |
| EC2 Reserved (4 baseline) | 1-year, no upfront | Save 35% = -$392 |
| Aurora MySQL | db.r6g.large writer + 2 readers | ~$390 |
| ElastiCache Redis | cache.r6g.large × 2 (Multi-AZ) | ~$185 |
| DynamoDB | PAY_PER_REQUEST, ~100M reads/day | ~$285 |
| S3 Storage | 500TB images + 50TB raw | ~$11,500 |
| S3 Intelligent Tiering | (saves ~40% on cold data) | -$4,600 |
| CloudFront | 5PB/month egress | ~$425,000 |
| CloudFront Reserved | 10TB committed capacity | Save 17% = -$72,250 |
| Lambda (processing) | 2M invocations × 8s avg | ~$320 |
| SQS | 100M messages/month | ~$40 |
| Rekognition | 2M images moderated | ~$1,000 |
| Route 53 | Hosted zone + health checks | ~$15 |
| WAF | 100M requests | ~$300 |
| Secrets Manager | 10 secrets | ~$4 |
| CloudWatch | Metrics, logs, alarms | ~$120 |
| **Total** | | **~$363,052/month** |

> **Note:** CloudFront egress dominates the cost (94%). This is typical for media platforms. Every 1% improvement in CDN cache hit rate saves ~$4,250/month.

### Cost Optimization Decisions

#### 1. CloudFront Saves Millions

```
Without CloudFront:
  20M image views/day × 120KB avg = 2.4TB/day from S3
  S3 data transfer: $0.09/GB × 2,400GB = $216/day = $6,480/month
  Plus: S3 GET requests: 20M × $0.0004/1000 = $8/day = $240/month

With CloudFront (95% cache hit):
  5% of 2.4TB hits S3 origin = 120GB/day from S3
  S3 transfer cost: $11/day = $324/month (97% saving)
  CloudFront cost: $425,000/month (but 95% better performance)
  
CloudFront is expensive — but the user experience (30ms vs 800ms) 
and reduced origin infrastructure cost justify it completely.
```

#### 2. S3 Intelligent Tiering

```
Image access pattern:
  0-7 days:   95% of views (newly uploaded content is trending)
  8-30 days:  4% of views (recent content, some traffic)
  31-90 days: 0.8% of views
  90+ days:   0.2% of views (archive)

Savings with S3 Intelligent Tiering:
  500TB total storage
  ~200TB in Standard ($0.023/GB) = $4,600/month
  ~200TB in Standard-IA ($0.0125/GB) = $2,500/month
  ~100TB in Archive ($0.004/GB) = $400/month
  Total: $7,500/month vs $11,500/month Standard-only
  Saving: $4,000/month ($48,000/year)
```

#### 3. DynamoDB: On-Demand vs Provisioned

```
Decision: PAY_PER_REQUEST (on-demand)

Reasoning:
  Peak: 500K reads/hour = 139 reads/sec
  Normal: 50K reads/hour = 14 reads/sec
  Ratio: 10:1 peak-to-average

  Provisioned at peak: 139 RCU × $0.00013/RCU-hour = $1.09/hour = $800/month
  On-demand: 100M reads/month × $0.000000125 = $12.50/month

  On-demand wins at this traffic profile (highly variable load).
  Switch to provisioned if reads become sustained and predictable (> 80% capacity utilization consistently).
```

#### 4. Lambda vs Always-On Workers

```
Image processing job:
  2M uploads/day × 8 seconds processing = 16M Lambda-seconds/day
  Lambda cost: 16M × 512MB × $0.0000166667 = $134/day × 30 = $4,000/month

  Equivalent EC2 (c6g.xlarge dedicated workers, 4 instances):
  4 × $0.136/hour × 720 = $392/month — MUCH cheaper!

  Conclusion: Switch to ECS Fargate Spot when upload volume exceeds
  2M/day consistently. Break-even: ~1.5M uploads/day.
  Current decision: Lambda (simpler, no ops) — plan ECS migration at scale.
```

---

## 8. Failure Scenarios

### Scenario 1: Aurora Database Overload

**Trigger:** Marketing campaign drives 10x spike in new user registrations. Aurora writer receives 5,000 INSERT/second (normal: 100/second).

**What Happens Without Mitigation:**
- Aurora writer CPU hits 100%
- Connection pool exhausted (max_connections = 1,000)
- New connections refused → 500 errors on registration endpoint
- Cascade: failed registrations → retry storms → more load → total outage

**Architecture Response:**

```
Immediate (0-30 seconds):
  → ElastiCache Redis: rate-limit registration to 50/sec per IP
  → WAF: detect registration burst pattern → throttle to 100 req/sec
  → ALB: queue incoming registration requests (connection draining)

Automatic (30-120 seconds):
  → CloudWatch alarm: AuroraCPU > 80% for 2 minutes
  → Alarm triggers: SNS → Lambda → increases Aurora instance class
  → RDS scale-up: db.r6g.large → db.r6g.xlarge (1-2 minute operation, brief failover)

Application-level mitigation:
  → Registration uses separate DynamoDB table for the queue
  → Users receive "Your account is being created" email → processed async
  → Decouples registration from Aurora write peak

Result: Registration degrades gracefully (queue-based), existing users unaffected.
```

### Scenario 2: ElastiCache Redis Failure (Total Cache Loss)

**Trigger:** Redis cluster suffers hardware failure during maintenance. Both primary and replica fail simultaneously (rare, but possible during patching).

**What Happens:**
- 90% of feed reads hit DynamoDB directly (cache miss)
- DynamoDB reads spike from 14/sec to 140/sec
- Aurora reads spike (session validation fallback)
- Response time increases from 50ms to 300ms
- Not a hard failure — a performance degradation

**Architecture Response:**

```
Phase 1 — Cache Stampede Protection (immediate):
  → Application: cache-aside pattern with jitter
  → Each request waits random 0-2 seconds before hitting DynamoDB
  → Prevents all 50,000 users from hitting DynamoDB at the same second
  → Thundering herd is spread across 2 seconds

Phase 2 — DynamoDB absorbs the load:
  → PAY_PER_REQUEST: auto-scales to handle 10x reads within seconds
  → No capacity exceeded errors — DynamoDB was designed for this
  → Response time: 300ms instead of 50ms — degraded but functional

Phase 3 — Redis recovers:
  → ElastiCache Multi-AZ: automatic failover in < 60 seconds
  → Read Replica promoted to Primary
  → Application reconnects (connection pooling handles this transparently)
  → Cache rebuilds organically as requests come in (lazy population)

Total user impact: 60 seconds of 300ms feeds instead of 50ms feeds.
No data loss. No hard failures. No manual intervention required.
```

### Scenario 3: Full us-east-1 Region Outage

**Trigger:** AWS us-east-1 experiences a cascading failure (as happened in Nov 2020). All services including EC2, RDS, S3 in us-east-1 are unavailable.

**What Happens (Without Multi-Region):**
- 100% of users get 502 errors
- Platform is completely down
- Revenue loss: ~$8,000/minute at 10M MAU scale

**Architecture Response:**

```
T+0 seconds:
  → Route 53 health check detects us-east-1 ALB returning 5xx
  → Health check: every 10 seconds, 3 consecutive failures required

T+30 seconds:
  → Route 53 marks us-east-1 as unhealthy
  → DNS failover begins: api.pixelvault.com → eu-west-1 ALB
  → DNS TTL: 60 seconds (cached responses still point to us-east-1)

T+60-90 seconds:
  → Most clients resolve DNS again → get eu-west-1 endpoint
  → Mobile apps have retry logic → reconnect automatically

T+90 seconds (user impact begins):
  → eu-west-1 ASG: min=2 instances running (warm standby)
  → DynamoDB Global Tables: eu-west-1 can immediately accept writes
  → Aurora Global Database: eu-west-1 reader promoted to writer (< 1 minute)

T+5 minutes:
  → eu-west-1 ASG scales from 2 → 20 instances (handles US traffic)
  → S3 CRR: images already replicated to eu-west-1 (15 min max lag)
  → New uploads: temporarily stored in eu-west-1, replicated back when us-east-1 recovers

T+15 minutes:
  → Full capacity in eu-west-1
  → US users experience 150-200ms latency (vs 30ms from us-east-1)
  → Platform is fully functional — slower, not down

Cost of multi-region standby: ~$2,000/month (worth every dollar)
Cost of 1 hour outage at scale: ~$480,000 in lost revenue + brand damage
```

---

## 9. Architecture Diagram

### How to Draw This in draw.io or Excalidraw

**Canvas Setup:** 1600×900px, white background, 16px grid.

**Layer 1 — Top (Users):**
- Three user icons: "US Users," "EU Users," "APAC Users"
- Arrow from all three converging to Route 53 box

**Layer 2 — Global Edge:**
- Route 53 box (blue) in center
- Arrow down to CloudFront box (orange)
- WAF shield icon overlapping CloudFront
- Arrow left from CloudFront to S3 bucket icon (yellow): "Media files"
- Arrow right from CloudFront to ALB icon (green): "API calls"

**Layer 3 — VPC Box:**
Draw a large dotted rectangle labeled "AWS VPC (us-east-1)"

Inside, two rows:
- **Public Subnet row:** ALB icon (already shown above), NAT Gateway icons
- **Private App Subnet row:** Three EC2 icons labeled "API Server ASG (2-50 instances)"
- **Private Data Subnet row:** Aurora icon, ElastiCache icon, RDS icon

**Layer 4 — Async Processing (right side of VPC):**
- SQS queue icon → Lambda worker icon
- Lambda → S3 bucket ("Processed Images")
- Lambda → Rekognition icon
- Lambda → SNS icon → mobile icons

**Layer 5 — External Data (bottom of VPC):**
- DynamoDB icon (labeled: posts, feeds, likes, follows)
- Aurora icon (labeled: users, accounts, billing)
- ElastiCache icon (labeled: feed cache, sessions)

**Layer 6 — Monitoring (right margin):**
- CloudWatch icon with lines connecting to every service

**Color coding:**
- Blue: networking (Route 53, VPC, subnets)
- Orange: CDN/content delivery (CloudFront, S3)
- Green: compute (EC2, Lambda, ALB)
- Red: database (Aurora, DynamoDB)
- Purple: cache/queue (ElastiCache, SQS)
- Yellow: security (WAF, IAM, Shield)

---

## 10. Repository Structure

```
project-6-pixelvault-platform/
│
├── README.md                        ← This file (full architecture document)
│
├── docs/
│   ├── architecture-diagram.md      ← Diagram drawing instructions
│   ├── deployment-guide.md          ← Step-by-step deployment walkthrough
│   ├── cost-estimate.md             ← Detailed monthly cost breakdown
│   └── lessons-learned.md          ← Architecture decisions and retrospective
│
├── terraform/
│   ├── variables.tf                 ← All input variables with descriptions
│   ├── vpc.tf                       ← VPC, subnets, NAT, route tables, VPC endpoints
│   ├── security.tf                  ← Security groups, KMS keys, WAF, IAM roles
│   ├── compute.tf                   ← ALB, EC2 ASG, Launch Template, scaling policies
│   ├── database.tf                  ← Aurora, DynamoDB tables + GSIs, ElastiCache
│   ├── storage.tf                   ← S3 buckets, lifecycle rules, CloudFront
│   ├── processing.tf                ← SQS queues, Lambda functions, EventBridge
│   ├── monitoring.tf                ← CloudWatch dashboard, alarms, log groups
│   └── outputs.tf                   ← All resource endpoints and ARNs
│
└── scripts/
    ├── bootstrap.sh                 ← Initial AWS account setup (CloudTrail, Config)
    └── load-test.sh                 ← k6 load test script for 50K concurrent users
```

---

## Interview Explanation Guide

### Opening Statement (30 seconds)

> *"I designed PixelVault, a global image sharing platform built for 10 million monthly active users. The architecture separates concerns into three tiers: a global edge layer handling 90% of traffic through CloudFront, a scalable compute layer using EC2 Auto Scaling for API requests, and a tiered data layer combining DynamoDB for high-speed reads, Aurora for transactional user data, and Redis for cache. Let me walk you through the key design decisions."*

### The 5 Questions Interviewers Always Ask

**Q1: How do you handle a viral event with 100x traffic spike?**

> *"The architecture has four automatic scaling layers. First, CloudFront absorbs 90% of read traffic — image views scale instantly with zero configuration because they're served from 450 edge locations. Second, Redis feeds are pre-cached for the biggest accounts, handling the read spike for the first 60 seconds. Third, SQS buffers the write workload — if 10,000 people re-share a post simultaneously, those processing jobs queue in SQS and Lambda processes them at its own rate. Fourth, EC2 Auto Scaling tracks ALB request count per target and launches instances when the queue builds — this takes 3-5 minutes, but the first three layers cover that window."*

**Q2: What happens when the database goes down?**

> *"Aurora is Multi-AZ. If the primary node fails, Aurora automatically promotes a reader replica in a different AZ within 30 seconds — no data loss, brief connection interruption that the application retries. For a full region failure, Aurora Global Database replicates with < 1 second lag to eu-west-1. We can promote the secondary to primary in under a minute, and Route 53 has already failed over DNS. The worst case is 15 minutes of US users connecting to Europe — slower, not down."*

**Q3: Why DynamoDB instead of a traditional SQL database for posts?**

> *"The primary access patterns for social media are key-value lookups: 'get this post,' 'get this user's feed,' 'does user A follow user B?' — these are all single-table lookups that DynamoDB does in 5 milliseconds at any scale. Aurora is excellent but at 50,000 concurrent connections, Aurora would need connection pooling, read replicas, and careful schema design to keep up. DynamoDB scales horizontally and automatically. I do use Aurora for user accounts and billing where I need ACID transactions — 'charge this card and create this account' must be atomic. Right tool for the right job."*

**Q4: How do you control cost given CloudFront is $363K/month?**

> *"The CDN cost is the honest reality of a media platform at scale. Without CloudFront, we'd need equivalent S3 egress and origin infrastructure — CloudFront actually saves money compared to self-managed delivery. The biggest lever is cache hit rate. Every 1% improvement saves $4,250/month. We target 95% by setting long TTLs (7 days) for images — they're immutable, new uploads get new URLs. We use S3 Intelligent Tiering which saves $48K/year by automatically moving cold images to cheaper storage. And we've committed to CloudFront reserved capacity pricing, saving 17%. As we grow, we'd negotiate AWS Enterprise Discount Program pricing."*

**Q5: How would you design this differently if starting over?**

> *"I'd add a service mesh earlier (AWS App Mesh or Istio on EKS) for better observability between microservices. I'd also implement a CQRS pattern more explicitly — Command (writes through API) separated from Query (reads from dedicated read models). I underestimated the fan-out problem for high-follower accounts — the 2,000,000-follower celebrity post requires a different strategy (pull-on-read instead of push-on-write for accounts above 100K followers). I'd also start with AWS CDK instead of Terraform — CDK's L2 constructs for ECS and EKS are significantly more maintainable. These are the real lessons learned from architecture at scale."*

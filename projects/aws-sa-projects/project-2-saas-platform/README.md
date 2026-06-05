# Project 2: Serverless SaaS Multi-Tenant Platform

> **Role Focus:** AWS Solutions Architect  
> **Scenario:** B2B SaaS startup  
> **Complexity:** Advanced  

---

## 1. Real-World Problem

**FormFlow** is a B2B SaaS startup building a form-builder and data collection platform (think Typeform + Zapier). They have 500 business customers ("tenants"), each with their own end users submitting form responses.

**The challenge:** The founding engineer built the MVP as a monolith on a single EC2 instance. As they approach Series A funding, investors are asking: *"How does this scale to 50,000 tenants without rebuilding it?"*

| Requirement | Target |
|-------------|--------|
| Tenants (current → target) | 500 → 50,000 |
| API requests (peak) | 10,000 req/sec |
| Data isolation | Tenant data must never leak across boundaries |
| Pricing model | Tiered: Free, Starter ($29/mo), Business ($99/mo), Enterprise |
| Availability | 99.9% (8.7 hours downtime/year) |
| Cold start tolerance | < 500ms for Starter/Business tiers |
| Cost at 0 traffic | $0 (scale to zero for free tier tenants) |

---

## 2. Architecture Overview

```
                    ┌─────────────────────────────────────────────┐
                    │              Global Edge Layer               │
                    │                                             │
  Tenants ────────▶ │   CloudFront + WAF (per-tenant rate limits) │
  End Users ──────▶ │   Route 53 (*.formflow.io wildcard CNAME)   │
                    └─────────────────┬───────────────────────────┘
                                      │
                    ┌─────────────────▼───────────────────────────┐
                    │           API Gateway (Regional)             │
                    │  - Usage Plans (per tier)                    │
                    │  - API Keys (per tenant)                     │
                    │  - Cognito JWT Authorizer                    │
                    │  - Request throttling (burst 5000)           │
                    └──────┬────────────┬────────────┬────────────┘
                           │            │            │
                  ┌────────▼───┐ ┌──────▼────┐ ┌────▼──────────┐
                  │  Lambda    │ │  Lambda   │ │  Lambda       │
                  │  /forms    │ │ /responses│ │  /webhooks    │
                  │  CRUD      │ │  Ingest   │ │  Dispatcher   │
                  └────────┬───┘ └──────┬────┘ └────┬──────────┘
                           │            │            │
                  ┌─────────▼────────────▼───────────▼──────────┐
                  │              DynamoDB (Single Table)          │
                  │  PK: TENANT#{id}  SK: FORM#{id}#RESP#{id}    │
                  │  GSI: by status, by created_at               │
                  └──────────────────────────────────────────────┘
                           │
                  ┌─────────▼───────────┐    ┌────────────────┐
                  │  EventBridge        │───▶ │  SQS + Lambda  │
                  │  (form.submitted)   │    │  (webhook fan- │
                  └─────────────────────┘    │   out to Zapier│
                                             │   Slack, etc.) │
                                             └────────────────┘
                  S3 (file uploads, CSV exports) — per-tenant prefixes
                  Cognito User Pools — one pool per tenant (isolation)
```

---

## 3. Multi-Tenancy Model: The Core Architecture Decision

**Three approaches — and why I chose "Pool Model with Tenant Isolation":**

| Model | Description | Pros | Cons | Chosen? |
|-------|-------------|------|------|---------|
| **Silo** | Separate AWS account per tenant | Perfect isolation, easy billing | $$$, operationally complex at 50k tenants | ❌ Enterprise-only |
| **Pool (single table)** | All tenants share infra, partition by tenant ID | Scale to zero, low cost, operationally simple | Requires careful isolation in code | ✅ Default |
| **Bridge** | Pool for small tenants, Silo for Enterprise | Best of both | Complex routing logic | ✅ Enterprise tier |

**Decision:** Pool model for Free/Starter/Business, Silo (dedicated AWS account) for Enterprise ($1k+/month) tenants.

---

## 4. AWS Services — Chosen and Why

### API & Auth Layer

| Service | Why Chosen | Alternative | Tradeoff |
|---------|-----------|-------------|----------|
| **API Gateway (HTTP API)** | 70% cheaper than REST API, JWT authorizers built-in, auto-scaling | REST API, ALB | HTTP API = simpler, cheaper; REST API needed for API keys/usage plans (chose REST for tier enforcement) |
| **Cognito User Pools** | Managed auth, JWT tokens, MFA, SAML federation for Enterprise | Auth0, Okta | Cognito cheaper (~$0.0055/MAU); Auth0 better UX and enterprise SSO; chose Cognito for cost at scale |
| **Lambda Authorizer** | Custom tenant validation before every Lambda invocation | Cognito JWT alone | Lambda Authorizer adds 100-200ms; necessary for checking tenant tier limits not stored in JWT |

### Compute

| Service | Why Chosen | Alternative | Tradeoff |
|---------|-----------|-------------|----------|
| **Lambda (Python 3.12)** | Zero servers, scales from 0 to 10k req/sec, 15-min max timeout | EC2, Fargate | Lambda = cold starts (100-500ms); Fargate = 0 cold start but ~$30-50/mo minimum cost; chose Lambda for scale-to-zero |
| **Lambda Provisioned Concurrency** | Eliminates cold starts for Business/Enterprise tiers | Keep-warm ping | Provisioned = guaranteed 0ms cold start; keep-warm = fragile hack; pay for Provisioned only on paid tiers |

### Data Layer

| Service | Why Chosen | Alternative | Tradeoff |
|---------|-----------|-------------|----------|
| **DynamoDB (Single Table)** | Scales to unlimited tenants, sub-ms reads, pay-per-request | Aurora Serverless, MongoDB | DynamoDB = no joins (model carefully); Aurora = rich SQL but minimum cost ~$50/mo; chose DynamoDB for true scale-to-zero |
| **S3** | File uploads (images, CSV imports), per-tenant prefixes with IAM | EFS | S3 = cheaper, globally accessible, no mount overhead; EFS = POSIX but irrelevant for object storage |
| **EventBridge** | Decoupled event routing without code-level fan-out | SNS, SQS direct | EventBridge = schema registry, content-based filtering, 100+ native targets; chose for extensibility |

---

## 5. DynamoDB Single-Table Design

```
Access patterns this design supports:
  1. Get all forms for a tenant          → PK=TENANT#123, SK begins_with(FORM#)
  2. Get a specific form                 → PK=TENANT#123, SK=FORM#abc
  3. Get all responses for a form       → PK=TENANT#123, SK begins_with(FORM#abc#RESP#)
  4. Get responses by status            → GSI: PK=TENANT#123, SK=STATUS#pending
  5. List tenants by plan               → GSI: PK=PLAN#business, SK=TENANT#123

Table structure:
  PK           SK                          Attributes
  ─────────────────────────────────────────────────────────────
  TENANT#t1    META                        plan, email, name, created_at
  TENANT#t1    FORM#f1                     title, fields[], status, created_at
  TENANT#t1    FORM#f1#RESP#r1             answers{}, submitted_at, ip_hash
  TENANT#t1    FORM#f1#RESP#r2             answers{}, submitted_at, ip_hash
  PLAN#starter TENANT#t1                  joined_at (for listing tenants by plan)
```

**Why single table over multiple tables?**  
All access patterns for a tenant's data can be satisfied in a single query when data is co-located under the same partition key. Multiple round-trips across multiple tables = higher latency and more Lambda execution time = higher cost.

---

## 6. Tenant Isolation — Security Architecture

### Data Isolation

```python
# Every Lambda handler enforces tenant context — no cross-tenant access possible
def get_forms(event, context):
    # tenant_id extracted from verified JWT — never from request body
    tenant_id = event['requestContext']['authorizer']['claims']['custom:tenant_id']
    
    response = table.query(
        KeyConditionExpression=Key('PK').eq(f'TENANT#{tenant_id}') &
                               Key('SK').begins_with('FORM#'),
        # Condition prevents any access to other tenant's partition
    )
```

### S3 Isolation

```hcl
# Each tenant gets an IAM policy that locks them to their S3 prefix
resource "aws_iam_policy" "tenant_s3" {
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "arn:aws:s3:::formflow-uploads/tenants/${tenant_id}/*"
      # The ${tenant_id} prefix = hard isolation enforced at IAM level
    }]
  })
}
```

### API Rate Limiting by Tier

| Tier | Requests/sec | Burst | Monthly quota |
|------|-------------|-------|---------------|
| Free | 10 | 20 | 10,000 |
| Starter | 100 | 500 | 1,000,000 |
| Business | 1,000 | 5,000 | Unlimited |
| Enterprise | Custom | Custom | Custom |

---

## 7. Scaling Strategy

### Lambda Concurrency Model

```
Request volume: 10,000 req/sec
Lambda duration: avg 100ms
Required concurrency: 10,000 × 0.1 = 1,000 concurrent executions

Configuration:
  - Account limit: 3,000 concurrent (request increase for production)
  - Reserved concurrency for /responses (critical): 500
  - Reserved concurrency for /webhooks: 200
  - Provisioned concurrency (Business/Enterprise): 50 pre-warmed
```

### DynamoDB Capacity

- **On-demand mode (default):** Pay-per-request. Scales instantly. Right for variable SaaS traffic.
- **Provisioned with auto-scaling:** More cost-effective at sustained high throughput (switch when > 5M reads/day consistently).

---

## 8. Cost Analysis

### Per-Tier Monthly Cost Attribution

| Component | Free Tenant | Starter Tenant | Business Tenant |
|-----------|-------------|----------------|-----------------|
| Lambda invocations | ~$0.00 | ~$0.08 | ~$1.20 |
| DynamoDB reads | ~$0.00 | ~$0.12 | ~$2.40 |
| API Gateway | ~$0.00 | ~$0.35 | ~$3.50 |
| S3 storage | ~$0.01 | ~$0.10 | ~$1.00 |
| **Cost per tenant** | **~$0.01** | **~$0.65** | **~$8.10** |
| **Revenue per tenant** | **$0** | **$29** | **$99** |
| **Margin** | N/A | **97.8%** | **91.8%** |

**Platform-wide (500 tenants, Day 1):** ~$400/month  
**Platform-wide (50,000 tenants, at scale):** ~$40,000/month → 40% revenue margin

---

## 9. Failure Modes and Handling

| Failure | Impact | Mitigation |
|---------|--------|-----------|
| Lambda cold start spike | 100-500ms latency burst | Provisioned concurrency for Business+; SQS buffer absorbs bursts |
| DynamoDB hot partition | Throttling for one tenant | Single-table design distributes load; adaptive capacity + DAX for Enterprise |
| Cognito outage | All auth fails | Tokens are JWTs — cached validation (5-min TTL) means auth continues during short Cognito outages |
| Webhook delivery failure | Tenant misses data | SQS DLQ captures failed webhooks; Lambda retries with exponential backoff; tenant receives failure notification |
| API Gateway throttle | 429 response to tenant | Usage plans per tenant prevent one tenant from starving others |

---

## 10. CAP Theorem Position

FormFlow chooses **AP (Available + Partition Tolerant)** for form submissions:

- A form response submitted while DynamoDB has a brief partition = **write succeeds** (DynamoDB is eventually consistent by default)
- Reading a just-submitted form response may return stale data for < 1 second
- **This is acceptable** — a respondent doesn't immediately view their own submission

For tenant billing and quota enforcement, **strong consistency reads** are used:
```python
# Quota checks use ConsistentRead=True to prevent free tier abuse
response = table.get_item(
    Key={'PK': f'TENANT#{tenant_id}', 'SK': 'QUOTA'},
    ConsistentRead=True  # pay 2x read units — worth it for billing accuracy
)
```

---

## 11. Architecture Diagram Layout

Draw in Excalidraw or draw.io:
- **Top row:** Users/Tenants → CloudFront → API Gateway
- **Middle row:** 3 Lambda functions side-by-side (forms, responses, webhooks)
- **Bottom row:** DynamoDB (center), S3 (left), EventBridge → SQS (right)
- **Right side panel:** Cognito User Pool, WAF rules
- Color coding: Blue = compute, Orange = storage, Purple = auth, Green = events

---

## Terraform Structure

```
terraform/
├── variables.tf      # Tenant configuration, Lambda settings, API throttle limits
├── api_gateway.tf    # REST API, resources, methods, usage plans, API keys
├── lambda.tf         # All Lambda functions, log groups, event source mappings
├── dynamodb.tf       # Single table, GSIs, backup configuration, auto-scaling
├── cognito.tf        # User Pool, App Client, custom attributes (tenant_id, plan)
├── eventbridge.tf    # Event bus, rules, targets for webhook fan-out
├── s3.tf             # Upload bucket, export bucket, per-prefix policies
├── iam.tf            # Lambda execution roles, S3 tenant policies, IRSA
└── outputs.tf        # API endpoint, Cognito pool ID, DynamoDB table name
```

---

## Setup Instructions

```bash
cd terraform/
terraform init
terraform plan -var="environment=production"
terraform apply

# After deploy — create test tenant
aws cognito-idp admin-create-user \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --username test@company.com \
  --user-attributes Name=custom:tenant_id,Value=TENANT001 \
                    Name=custom:plan,Value=starter

# Test the API
API_ENDPOINT=$(terraform output -raw api_endpoint)
curl -X POST "$API_ENDPOINT/forms" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"Contact Form","fields":[{"type":"text","label":"Name"}]}'
```

---

## Interview Talking Points

**Q: Why DynamoDB single-table over separate tables per tenant?**  
Single table keeps all a tenant's data co-located. One DynamoDB query returns forms + responses without cross-table joins. Separate tables per tenant would mean 50,000 DynamoDB tables at scale — operationally unmanageable and AWS has a soft limit of 2,500 tables per account.

**Q: How do you prevent one tenant from affecting others ("noisy neighbor")?**  
Three layers: (1) API Gateway usage plans throttle per-API-key at the edge before Lambda is invoked, (2) Lambda reserved concurrency ensures critical functions always have capacity, (3) DynamoDB adaptive capacity automatically redistributes throughput away from hot partitions within minutes.

**Q: Why not use Aurora Serverless v2 instead of DynamoDB?**  
Aurora Serverless v2 has a minimum of 0.5 ACUs (~$43/month). DynamoDB on-demand costs $0 at zero traffic. At 50,000 free-tier tenants with near-zero traffic, Aurora Serverless v2 would cost $43/month total; DynamoDB costs $0. However, if we needed complex SQL queries or transactions across many entity types, I'd reconsider Aurora Serverless v2.

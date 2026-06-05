# Concept 2: Compute — EC2, Auto Scaling, and Load Balancing

## EC2 — Elastic Compute Cloud

An **EC2 instance** is a virtual server running in AWS. You choose:
- **Instance type** — CPU, memory, network bandwidth
- **AMI (Amazon Machine Image)** — the OS and pre-installed software
- **Storage** — EBS volumes (like a virtual hard drive)
- **Networking** — which VPC/subnet, security groups, public IP or not

### Instance Type Naming Convention

```
c6i.xlarge
│ │ │    └── Size: nano < micro < small < medium < large < xlarge < 2xlarge...
│ │ └─────── Generation: 6 (newer = faster/cheaper than 5, 4, 3)
│ └───────── Processor: i = Intel, a = AMD, g = AWS Graviton (ARM)
└─────────── Family:
               c = Compute optimized (web servers, API servers)
               m = General purpose (balanced CPU/memory)
               r = Memory optimized (databases, caches)
               t = Burstable (dev/test, variable load)
               p/g = GPU (ML, graphics)
```

**In the portfolio:**
- `c6i.xlarge` — 4 vCPU, 8GB RAM — API servers (compute-heavy, not memory-heavy)
- `db.r6g.2xlarge` — 8 vCPU, 64GB RAM — Aurora (memory-heavy for buffer pool)
- `cache.r7g.xlarge` — 4 vCPU, 26GB RAM — Redis (memory is the product)

### Pricing Models

| Model | Cost | When to Use |
|-------|------|-------------|
| **On-Demand** | Full price, by the hour | Unpredictable workloads, short-lived |
| **Reserved (1yr)** | ~40% discount | Always-on resources (DB, baseline web) |
| **Reserved (3yr)** | ~60% discount | Stable, long-term workloads |
| **Spot** | ~70-90% discount | Interruptible work (batch, CI/CD, stateless web) |
| **Savings Plans** | ~40-66% discount | Flexible commitment (applies across instance types) |

**The portfolio strategy:** 3 On-Demand baseline instances + Spot for everything above baseline. If AWS reclaims a Spot instance, the ALB stops sending traffic to it in 30 seconds, and Auto Scaling replaces it.

---

## Launch Templates — Repeatable Instance Configuration

A **Launch Template** defines everything about how to create an EC2 instance: AMI, instance type, security groups, IAM role, user data script, EBS volumes. 

Think of it as a blueprint — the Auto Scaling Group uses it to create identical instances at any scale.

**Key settings used in the portfolio:**

```hcl
metadata_options {
  http_tokens = "required"  # IMDSv2 — blocks SSRF attacks
}

block_device_mappings {
  ebs {
    encrypted = true  # All volumes encrypted at rest
  }
}
```

**IMDSv2 explained:** Every EC2 instance has a metadata endpoint at `169.254.169.254` that returns the instance's IAM credentials. Without IMDSv2, a SSRF (Server-Side Request Forgery) bug in your app lets an attacker steal those credentials with a single `curl` request. IMDSv2 requires a session token obtained via a PUT request first — SSRF attacks can't do PUTs.

---

## Auto Scaling Groups — Elastic Capacity

An **Auto Scaling Group (ASG)** maintains a fleet of EC2 instances and automatically adjusts size based on demand.

### How It Works

```
CloudWatch Alarm: CPU > 60% for 3 minutes
         │
         ▼
    Scaling Policy fires
         │
         ▼
    ASG launches new instances using Launch Template
         │
         ▼
    ALB Health Check passes
         │
         ▼
    New instances receive traffic
```

### Three Types of Scaling Policies

**1. Target Tracking (used in all projects — simplest)**
```
"Keep CPU at 60%"
```
ASG calculates how many instances are needed and adjusts automatically. AWS handles the math.

**2. Step Scaling**
```
CPU 60-70% → add 2 instances
CPU 70-80% → add 5 instances
CPU >80%   → add 10 instances
```
More control but more configuration.

**3. Scheduled Scaling**
```
"Every Friday at 5pm ET, set desired = 20"
```
You know traffic is coming (flash sale, event) — pre-warm before the spike.

### Key ASG Configuration

```
min_size     = 3   ← Never go below this (covers one AZ failure)
max_size     = 100 ← Never go above this (cost cap)
desired      = 6   ← Current target
```

### Instance Refresh

When you update a Launch Template (new AMI, new user data), **Instance Refresh** replaces old instances with new ones in a rolling fashion:

```
min_healthy_percentage = 75  → always keep 75% healthy during refresh
instance_warmup = 120        → wait 2 min before considering new instance healthy
```

Without this, you'd have to manually terminate instances one by one.

---

## Application Load Balancer (ALB)

An **ALB** distributes incoming HTTP/HTTPS traffic across multiple EC2 instances. It operates at Layer 7 (HTTP) — it understands URLs, headers, cookies.

```
User → ALB → Target Group → EC2 instances
```

### Key ALB Concepts

**Target Group:** The set of instances (or Lambda functions, IPs) the ALB routes to. Health checks run against the target group.

**Health Check:** ALB periodically hits `/health` on each instance:
- If it gets a 200 → instance is healthy, send traffic
- If it fails 3 times → instance is unhealthy, stop sending traffic
- New instances must pass health check before receiving traffic (warm-up protection)

**Listener Rules:** ALB can route differently based on path or host:
```
/api/*      → API Target Group (EC2)
/images/*   → CloudFront (or directly to S3)
/ws         → WebSocket Target Group
```

### ALB vs NLB vs Gateway LB

| LB Type | Layer | Protocol | Use Case |
|---------|-------|----------|----------|
| **ALB** | 7 (HTTP) | HTTP, HTTPS, WebSocket | Web apps, REST APIs, microservices |
| **NLB** | 4 (TCP/UDP) | TCP, UDP, TLS | Low latency, high throughput, static IP needed |
| **Gateway LB** | 3 (IP) | All IP traffic | Traffic inspection (firewall appliances) |

**When to use NLB over ALB:** Your protocol is not HTTP (e.g., gaming server using UDP), or you need static IPs for client whitelisting.

### SSL/TLS Termination

The ALB handles HTTPS decryption (using an ACM certificate), then forwards HTTP to instances internally. This means:
- EC2 instances only handle unencrypted HTTP (port 8080)
- No SSL certificates need to be installed on EC2
- ACM certificates are free and auto-renewed

```
Client → HTTPS 443 → ALB (decrypts) → HTTP 8080 → EC2
```

---

## Mixed Instances Policy — Spot + On-Demand

The portfolio uses this pattern for cost optimization:

```
on_demand_base_capacity = 3          → always keep 3 On-Demand (stable baseline)
on_demand_percentage_above_base = 25 → above 3, use 25% On-Demand, 75% Spot
spot_allocation = "capacity-optimized" → pick Spot pools least likely to be interrupted
```

**Result at desired=6:**
- 3 On-Demand (base)
- 1 On-Demand (25% of the 3 above base)
- 2 Spot (75% of the 3 above base)

**Why capacity-optimized for Spot?** AWS has more Spot capacity in some pools than others. `capacity-optimized` picks the deepest pool — lower interruption rate. The alternative `lowest-price` picks cheapest pool — higher interruption risk.

---

## User Data Script

A **User Data** script runs once when an EC2 instance first launches. Used to bootstrap the instance:

```bash
#!/bin/bash
dnf update -y
dnf install -y amazon-cloudwatch-agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c ssm:/myapp/cloudwatch-config -s
systemctl start myapp
```

**Production pattern:** Don't put the full application install in user data. Instead:
1. Bake a custom AMI with the app pre-installed (faster launch, 30s vs 5min)
2. Use user data only for environment-specific configuration (env vars, config file)
3. Or use AWS Systems Manager (SSM) Run Command for post-launch configuration

---

## IAM Instance Profile

An **IAM Instance Profile** gives your EC2 instance an identity — it can then call AWS APIs without storing credentials in code or environment variables.

```
EC2 instance → IAM Role → IAM Policy → Allow s3:PutObject on my-bucket
```

The SDK running on the EC2 instance automatically discovers credentials from the instance metadata (IMDSv2). No `AWS_ACCESS_KEY_ID` needed in code.

**Least privilege principle:** Only grant what the instance actually needs.
```
✅ Allow s3:PutObject on arn:aws:s3:::my-bucket/*
❌ Allow s3:* on *
```

---

## Interview Questions for This Concept

**Q: What happens when an EC2 instance fails a health check?**
> The ALB stops sending new requests to that instance within 30 seconds. The ASG marks the instance as unhealthy and terminates it, then launches a replacement using the Launch Template. The new instance must pass health checks before receiving traffic. Total recovery time is typically 2-5 minutes depending on the warmup period.

**Q: What's the difference between horizontal and vertical scaling?**
> Vertical scaling means making one instance bigger (c6i.xlarge → c6i.2xlarge). It's simple but has a ceiling (biggest instance in a family) and requires downtime to change instance type. Horizontal scaling means adding more instances of the same size. It's harder (requires stateless app design, load balancing) but has no ceiling and zero downtime. For web applications, horizontal scaling is always preferred.

**Q: Why use Spot instances for the web tier?**
> Web tier EC2 instances are stateless — they don't store session data locally (sessions go in ElastiCache Redis). When AWS reclaims a Spot instance with 2 minutes notice, the ASG terminates it gracefully, the ALB stops sending traffic, and the ASG launches a replacement. Users experience nothing. Spot saves 70% vs On-Demand — at 10 instances of c6i.xlarge, that's ~$1,200/month saved.

**Q: What is IMDSv2 and why does it matter?**
> IMDSv2 requires a session token to access instance metadata, including the IAM role credentials. Without it, a single SSRF vulnerability in your application lets an attacker steal AWS credentials with one HTTP GET request. With IMDSv2, the attacker would need to make a PUT request first to get the token — SSRF is GET-only, so the attack fails. It's a single line of Terraform config that closes a major attack vector.

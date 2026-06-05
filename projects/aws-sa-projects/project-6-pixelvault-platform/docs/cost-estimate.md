# PixelVault Cost Estimate

**Scale:** 10M MAU | 2M uploads/day | 20M image views/day | 50K concurrent peak  
**Region:** us-east-1 (primary) | Pricing as of 2025

---

## Monthly Cost Breakdown

| Service | Configuration | Monthly Cost | % of Total |
|---------|--------------|-------------|------------|
| **CloudFront** | 600TB egress/month (20M views × ~30KB avg) | $51,000 | 14.1% |
| **Aurora MySQL** | db.r6g.2xlarge writer + 2 readers | $4,320 | 1.2% |
| **EC2 Auto Scaling** | 6 × c6i.xlarge avg (25% On-Demand, 75% Spot) | $1,680 | 0.5% |
| **ElastiCache Redis** | 3 shards × cache.r7g.xlarge × 3 nodes | $5,832 | 1.6% |
| **S3 Storage** | 500TB processed images + 100TB originals | $14,400 | 4.0% |
| **S3 Requests** | 2M PUT + 600M GET/month | $2,640 | 0.7% |
| **Lambda** | Image processor + fan-out + moderation | $420 | 0.1% |
| **SQS** | Fan-out + moderation queues | $180 | 0.05% |
| **WAF** | Bot control + 6 rules + 600M requests | $18,600 | 5.1% |
| **NAT Gateways** | 3 AZs × ~500GB data processed | $660 | 0.2% |
| **VPC Endpoints** | S3 + DynamoDB (Gateway = free), 4 Interface | $360 | 0.1% |
| **DynamoDB** | On-demand — feeds + notifications | $1,200 | 0.3% |
| **Secrets Manager** | 4 secrets × 30-day rotation | $12 | <0.1% |
| **CloudWatch** | Logs + metrics + dashboard + alarms | $480 | 0.1% |
| **CloudTrail** | Multi-region trail + S3 storage | $96 | <0.1% |
| **ACM** | TLS certificate | $0 | 0% |
| **Route 53** | Hosted zone + queries | $24 | <0.1% |
| **Rekognition** | 2M images/day × $0.001/image | $60,000 | 16.6% |
| **Data Transfer** | Inter-AZ + regional | $1,800 | 0.5% |
| **Misc / Buffer** | CloudFront logs, X-Ray, misc | $600 | 0.2% |
| **TOTAL** | | **~$163,504/mo** | 100% |

> Note: Rekognition is the second-largest cost driver. At production scale, this is often replaced with a custom ML model on SageMaker or a third-party moderation API (e.g., Amazon Rekognition Custom Labels, Hive Moderation) at lower per-image cost.

---

## Dominant Cost Driver: CloudFront + Rekognition

CloudFront egress and Rekognition together account for ~31% of the bill at 10M MAU. Both scale linearly with user count — architectural leverage is needed to control these.

### CloudFront Egress Math

```
20M views/day × 30 requests/view (1 full image + thumbnails) 
= 600M requests/day
= 18B requests/month

Avg image size served:
- thumbnail (150px JPEG): ~8KB
- medium (600px JPEG): ~35KB
- full (1200px JPEG): ~80KB
- Weighted avg (60% thumbs, 30% medium, 10% full): ~20KB

18B requests × 20KB = ~360TB/month
CloudFront tiered pricing: ~$0.0085/GB blended = ~$3,060/month

+ HTTPS request cost: 18B × $0.01/10K = $18,000/month
```

CloudFront request charges (not just data transfer) dominate at high request volume.

---

## Cost Optimization Strategies

### 1. S3 Intelligent Tiering — Saves ~$48K/year

Images older than 30 days transition to Standard-IA automatically:
- Standard: $0.023/GB
- Standard-IA: $0.0125/GB (after 30 days)
- Glacier IR: $0.004/GB (originals after 90 days)

For 600TB of processed images where 80% are >30 days old:
```
Without IT: 600TB × $0.023 = $13,800/month
With IT:    120TB × $0.023 + 480TB × $0.0125 = $2,760 + $6,000 = $8,760/month
Savings:    $5,040/month = $60,480/year
```

### 2. CloudFront Cache Hit Rate — Reduces Origin Load 95%

Images are immutable (processed once, served forever). With `max-age=31536000`:
- Cache hit rate: ~95% after warm-up (images are re-requested frequently)
- Origin shield absorbs 99% of misses before they hit S3
- Each cache miss costs $0.0085/GB vs $0.000 on cache hit
- Effective CloudFront cost per image: ~$0.0000002 at 95% hit rate

**Key lever:** Cache hit rate from 80% → 95% cuts CloudFront origin costs by 75%.

### 3. EC2 Spot for API Tier — Saves ~$1,200/month

```
On-Demand c6i.xlarge: $0.204/hr × 6 instances × 730 hrs = $894/month
Spot c6i.xlarge:      $0.062/hr × 4.5 instances × 730 hrs = $204/month
On-Demand base (3):   $0.204/hr × 1.5 instances × 730 hrs = $224/month
Total with Spot mix:  ~$428/month
Savings vs all On-Demand: $466/month
```

Mixed instances policy uses `capacity-optimized` allocation strategy — selects the Spot pool with deepest capacity, minimizing interruptions.

### 4. Reserved Instances for Aurora and Redis — Saves ~$3,500/month

Aurora and Redis are always-on, predictable workloads — ideal for 1-year reservations:

| Service | On-Demand | 1-yr Reserved | Savings |
|---------|-----------|--------------|---------|
| db.r6g.2xlarge (×3) | $4,320/mo | $2,808/mo | $1,512/mo |
| cache.r7g.xlarge (×9) | $5,832/mo | $3,888/mo | $1,944/mo |
| **Total** | **$10,152/mo** | **$6,696/mo** | **$3,456/mo** |

Annual savings: **$41,472**

### 5. Rekognition Optimization — Potential $40K/month savings

At 2M uploads/day, Rekognition costs ~$60,000/month. Alternatives:

| Option | Cost | Trade-off |
|--------|------|-----------|
| Rekognition (current) | $60K/mo | Managed, no ops overhead |
| Rekognition Custom Labels | ~$30K/mo | Requires labeled training data |
| SageMaker + custom model | ~$8K/mo | Requires ML expertise, 2-4 weeks to deploy |
| Hive Moderation API | ~$4K/mo | Third-party, privacy considerations |

For a startup: start with Rekognition (no ops), migrate to SageMaker at scale.

---

## Cost by Growth Stage

| Stage | MAU | Monthly Cost | Cost/User |
|-------|-----|-------------|-----------|
| Launch | 100K | ~$8,200 | $0.082 |
| Growth | 1M | ~$24,500 | $0.025 |
| Scale | 10M | ~$163,500 | $0.016 |
| Hyper-scale | 100M | ~$820,000 | $0.008 |

Cost per user decreases with scale — CloudFront and S3 have volume pricing tiers, and Reserved Instance coverage increases.

---

## Cost vs Competitors (Self-Hosted)

| Approach | Monthly Cost at 10M MAU | Trade-off |
|----------|------------------------|-----------|
| AWS (this architecture) | $163,500 | Zero ops for managed services |
| AWS (fully optimized) | ~$95,000 | Reserved, Spot, custom moderation |
| GCP equivalent | ~$155,000 | Similar pricing, different managed services |
| Self-hosted (bare metal) | ~$80,000 | Full ops team required ($500K+/yr labor) |

**Verdict:** AWS managed services trade ~$80K/month in infrastructure cost for eliminating ~3 FTEs of ops work. At 10M MAU, that trade is almost always worth it.

---

## Interview Talking Point

> "The biggest cost surprise was that CloudFront request charges — not data transfer — dominate at 10M MAU. 18 billion requests per month at $0.01/10K = $18,000 just in request fees. The architectural response was maximizing cache hit rate: immutable image URLs, one-year cache TTL, Origin Shield to absorb misses. Every percentage point of cache hit rate is worth roughly $600/month at this scale."

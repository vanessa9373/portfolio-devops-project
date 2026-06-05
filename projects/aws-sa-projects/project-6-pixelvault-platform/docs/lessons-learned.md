# PixelVault — Lessons Learned & Interview Guide

## Architecture Decisions I'd Defend in Any Interview

---

### 1. Why Two Databases (Aurora + DynamoDB) Instead of One?

**The mistake beginners make:** Choosing one database for everything.

**The real answer:** Each database is optimized for a different access pattern.

| Data | Database | Why |
|------|----------|-----|
| User profiles, follows, post metadata | Aurora MySQL | Relational — `JOIN` between users and posts is natural |
| Pre-computed feeds | DynamoDB | Key-value — feed reads are always `user_id → [post_ids]`, no joins needed |
| Notification history | DynamoDB | Append-only, TTL-expirable, high write throughput |
| Like/follow counts | Redis | Atomic `INCR` at sub-millisecond latency, no DB writes per action |

**The design principle:** Match the access pattern to the data model. Forcing relational queries into DynamoDB or key-value lookups into Aurora creates unnecessary complexity.

**Interview follow-up:** "Could you use DynamoDB for everything?" — Yes, but you'd rebuild SQL JOIN semantics in application code. For a social graph (followers of followers, mutual friends), that's a losing trade.

---

### 2. Why Pre-Compute Feeds Instead of Querying on Read?

**The naive approach:** On feed load, run:
```sql
SELECT p.* FROM posts p
JOIN follows f ON f.followee_id = p.user_id
WHERE f.follower_id = ? 
ORDER BY p.created_at DESC 
LIMIT 20
```

**The problem:** At 10M users with avg 300 follows each, this query touches ~300 rows per user, runs on every feed refresh (every 30s on mobile), and hits the Aurora reader. That's 10M × 2 refreshes/hr × 300 rows = 6 billion row reads per hour. Aurora would need 50+ read replicas.

**The solution:** Fan-out on write. When user A posts:
1. API server enqueues a fan-out job to SQS
2. Lambda reads A's follower list in batches of 500
3. Writes one DynamoDB entry per follower: `{user_id: follower, post_id: ..., timestamp: ...}`
4. Feed read = single DynamoDB query: `user_id = me ORDER BY timestamp DESC LIMIT 20`

**The trade-off:** Write amplification. One post by a user with 1M followers = 1M DynamoDB writes. For celebrities, this is expensive. **Instagram's actual solution:** Hybrid — fan-out for regular users, pull-on-read for celebrities (verified accounts). The threshold is typically ~10K followers.

---

### 3. Why CloudFront + S3 Instead of Serving Images from EC2?

**The question interviewers ask:** "Why not just store images on EC2 EBS and serve them from your app servers?"

**The answer:**
1. **Scale:** EBS is per-instance. CloudFront + S3 is globally distributed with no capacity planning.
2. **Cost:** EC2 egress = $0.09/GB. CloudFront = $0.0085/GB (blended). S3 storage = $0.023/GB vs EBS = $0.08/GB-month.
3. **Performance:** CloudFront serves from 450+ edge locations. EC2 serves from one region.
4. **Separation of concerns:** Stateless API servers scale independently from image storage.

**The security insight:** Processed images live in a private S3 bucket. CloudFront can read via OAC (Origin Access Control). Direct S3 access is blocked. Users can never bypass CloudFront to hit the bucket directly — no hotlinking, no cost leakage.

---

### 4. What Happens When a Post Goes Viral?

**Scenario:** A celebrity with 5M followers posts. Within 60 seconds, 500K users refresh their feeds.

**Layer-by-layer response:**

| Layer | What happens | AWS service |
|-------|-------------|-------------|
| DNS | Resolves to nearest CloudFront PoP | Route 53 latency-based |
| CDN | Image requests hit edge cache (95% hit rate) | CloudFront |
| WAF | IP rate limit (2K req/5min) blocks scrapers | WAF Bot Control |
| ALB | Distributes 500K feed API requests across instances | ALB |
| ASG | CPU hits 70% → scale-out triggered → +10 instances in 3min | EC2 Auto Scaling |
| Cache | Feed pre-computed, Redis returns in <1ms | ElastiCache Redis |
| DB | Readers handle profile lookups, writer untouched | Aurora |
| Fan-out | 5M DynamoDB writes via Lambda (batched, async) | SQS + Lambda |

**The key insight:** The viral spike never touches Aurora for feed reads. Redis serves pre-computed feeds. Aurora only serves profile lookups and post metadata (much smaller query volume). The SQS fan-out is async — the posting user gets a 200ms response while the 5M feed writes happen over the next 2-3 minutes.

---

### 5. What Fails First at 10x Traffic?

**Interviewers love this question.** Think through each layer:

**Most likely bottleneck: Aurora writer**
- At 10x write traffic (20M uploads/day), the writer handles inserts for posts, likes, follows
- At ~2,300 writes/second, Aurora MySQL begins to saturate connections
- **Fix:** Connection pooling via RDS Proxy (adds ~5ms but handles 10K concurrent connections), write buffering via SQS

**Second bottleneck: Redis memory**
- Feed cache entries at 10x scale: 100M users × 50 entries × ~200 bytes = ~1TB needed
- Current config: 3 shards × r7g.xlarge = ~96GB total
- **Fix:** Add shards (cluster mode scales horizontally), reduce feed cache TTL from 5min to 1min

**Third bottleneck: NAT Gateways**
- Lambda functions in VPC route outbound traffic through NAT
- At 10x, NAT data processing costs spike
- **Fix:** VPC Interface Endpoints eliminate NAT traffic for AWS service calls (S3, DynamoDB already use Gateway endpoints which are free)

**What doesn't fail:** CloudFront, S3, DynamoDB, SQS — these are AWS-managed and scale to essentially any load without configuration changes.

---

### 6. How Would You Handle the Hot Partition Problem?

**The scenario:** A viral post accumulates 50,000 likes per minute. Each like is a DynamoDB write to the same partition key.

**Why it's a problem:** DynamoDB partitions have a write limit of 1,000 WCU/second per partition. 50,000 writes/minute = ~833 writes/second — right at the limit. A spike to 60,000 likes/minute causes throttling and 400 errors.

**Solution: Counter Sharding**

Instead of one item per post:
```
POST#abc123 → { like_count: 50000 }
```

Use 10 sharded counters:
```
POST#abc123#SHARD#0 → { likes: 5100 }
POST#abc123#SHARD#1 → { likes: 4980 }
...
POST#abc123#SHARD#9 → { likes: 5020 }
```

Write logic:
```python
shard = random.randint(0, 9)
table.update_item(
    Key={'pk': f'POST#{post_id}#SHARD#{shard}'},
    UpdateExpression='ADD likes :one',
    ExpressionAttributeValues={':one': 1}
)
```

Read (display count):
```python
responses = table.batch_get_item(RequestItems={
    table_name: {
        'Keys': [{'pk': f'POST#{post_id}#SHARD#{i}'} for i in range(10)]
    }
})
total = sum(item.get('likes', 0) for item in responses['Responses'][table_name])
```

**Trade-off:** 10 reads instead of 1 to get the like count. Acceptable because displaying the count happens once per page load, not per like event.

---

### 7. The IMDSv2 Requirement — Why It Matters

Every EC2 instance has a metadata endpoint at `http://169.254.169.254/`. An attacker who achieves SSRF (Server-Side Request Forgery) can query this URL from your app server and steal the IAM role credentials.

**With IMDSv2 (`http_tokens = "required"`):**
- Metadata requests require a session token obtained via a PUT request first
- SSRF attacks using GET requests cannot obtain the session token
- Closes the most common credential exfiltration path for EC2 workloads

**In the Terraform:**
```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"  # IMDSv2 enforced
  http_put_response_hop_limit = 1           # blocks container-to-host escalation
}
```

This is a detail that separates junior from mid-level candidates in security conversations.

---

### 8. What I Would Do Differently at 100M MAU

1. **Replace Aurora with Aurora Global Database** — active-active multi-region reads, <1 second cross-region replication lag, automatic failover across regions.

2. **Add a CDN-level edge compute layer** — CloudFront Functions or Lambda@Edge for auth token validation at the edge. Eliminates round-trips to ALB for simple auth checks on image requests.

3. **Migrate fan-out to Kinesis** — SQS fan-out works at 10M MAU but Kinesis gives ordered delivery per-user and native integration with Flink for real-time feed analytics.

4. **Replace custom feed computation with a graph database** — At 100M users, Neptune or a dedicated social graph service (similar to what Facebook built with TAO) handles relationship traversal more efficiently than DynamoDB.

5. **Custom content moderation model** — Rekognition at 200M uploads/month (100M MAU × 2 uploads/day) costs ~$600K/month. A custom SageMaker model amortizes training cost and cuts inference cost by 90%.

---

## Three Questions That Will Come Up in Every Interview

**Q: "Why did you choose Aurora over RDS MySQL?"**
> "Aurora is API-compatible with MySQL but delivers up to 5x higher throughput on the same hardware. At 10M MAU with 2M daily writes, the bottleneck becomes connection count and write throughput — both of which Aurora handles better through its distributed storage layer. The key practical difference: Aurora reader endpoints auto-discover new read replicas as they're added, while RDS requires DNS TTL propagation."

**Q: "How do you handle a database failover?"**
> "Aurora promotes a read replica to writer in under 30 seconds. During failover, the writer endpoint resolves to the new primary — no DNS change needed from the application side. We set `aurora_failover_target = true` on the replica nearest to the writer to minimize failover time. The 30-second window is covered by retry logic in the application — we retry failed DB writes up to 3 times with 100ms exponential backoff."

**Q: "What's the RTO if us-east-1 goes down?"**
> "We'd trigger a failover to us-west-2 using Route 53 health checks that automatically reroute traffic. S3 Cross-Region Replication keeps the processed images bucket in sync with <15 minutes lag. Aurora Global Database would replicate with <1 second lag — though at current scale we'd use a manual point-in-time restore from the automated 35-day backup window. DynamoDB Global Tables are active-active so that layer is transparent. The RTO is approximately 15 minutes, driven by Aurora restore time and DNS propagation."

# Project 4: Global Media Streaming & Content Delivery Platform

> **Role Focus:** AWS Solutions Architect  
> **Scenario:** Video-on-demand media company  
> **Complexity:** Advanced  

---

## 1. Real-World Problem

**StreamVault** is a video-on-demand platform launching in 3 countries simultaneously (US, UK, Brazil). They have 500,000 subscribers who expect Netflix-quality streaming: instant playback, adaptive quality based on network speed, content that's protected from piracy, and zero buffering even during peak concurrent streams (Sunday night at 9 PM).

| Requirement | Target |
|-------------|--------|
| Concurrent streams (peak) | 50,000 |
| Supported resolutions | 360p, 480p, 720p, 1080p, 4K |
| Content protection | DRM (digital rights management), signed URLs |
| Startup latency | < 3 seconds to first frame |
| Origin egress bandwidth | Minimize (CDN cache hit > 90%) |
| Global regions | US-East, EU-West, South America |
| Availability | 99.99% for playback |
| New title ingest | Video ready to stream < 30 minutes after upload |

---

## 2. Architecture Overview

```
  ┌────────────────────────────────────────────────────────────────┐
  │                    CONTENT INGEST PIPELINE                      │
  │                                                                │
  │  Filmmaker/Studio ──▶ S3 Upload (raw)                          │
  │                            │                                  │
  │                    S3 Event ──▶ Lambda ──▶ MediaConvert        │
  │                                               │               │
  │                                   Transcodes to HLS/DASH      │
  │                                   (8 renditions: 360→4K)      │
  │                                               │               │
  │                                    S3 (processed videos)      │
  └──────────────────────────────────────────────┬────────────────┘
                                                 │
  ┌──────────────────────────────────────────────▼────────────────┐
  │                    GLOBAL DELIVERY LAYER                        │
  │                                                                │
  │   CloudFront Distribution                                      │
  │   ├── Origin Shield (us-east-1) ──▶ S3 video origin           │
  │   ├── 450+ Edge Locations                                      │
  │   ├── Signed URLs (content protection)                         │
  │   └── Field-Level Encryption (for auth tokens)                │
  │                                                                │
  │   Route 53 ──▶ API Gateway ──▶ Lambda                          │
  │              (playback auth)   (generates signed URLs)         │
  └────────────────────────────────────────────────────────────────┘
                                                 │
  ┌──────────────────────────────────────────────▼────────────────┐
  │                       DATA LAYER                               │
  │                                                                │
  │  DynamoDB                    ElastiCache Redis                 │
  │  - Content catalog           - Session tokens                  │
  │  - User entitlements         - Signed URL cache (60s TTL)      │
  │  - Watch history             - Trending content cache          │
  │  - User profiles                                              │
  └────────────────────────────────────────────────────────────────┘

  Monitoring: CloudFront Real-time logs ──▶ Kinesis ──▶ Lambda ──▶ CloudWatch
  Playback errors trigger immediate alarm
```

---

## 3. Architecture Deep Dive: The Video Pipeline

### Step 1: Content Ingest

When a new title is uploaded by the studio team:

```
1. Studio uploads raw .mp4 to S3 raw-ingest bucket (multipart upload for large files)
2. S3 Event Notification triggers Lambda (ingest-orchestrator)
3. Lambda creates MediaConvert job with 8 output renditions:
   - 360p  @ 400 Kbps  (for mobile/poor connections)
   - 480p  @ 800 Kbps  (standard mobile)
   - 720p  @ 2.5 Mbps  (HD)
   - 1080p @ 5 Mbps    (Full HD)
   - 1080p @ 8 Mbps    (Full HD high quality)
   - 4K    @ 16 Mbps   (Ultra HD)
   - Audio-only 128Kbps (for background play)
   - Thumbnails every 10 seconds (for seek preview)
4. MediaConvert outputs HLS (.m3u8 manifest + .ts segments) to processed S3 bucket
5. EventBridge rule: MediaConvert COMPLETE → Lambda updates DynamoDB content catalog
6. CloudFront invalidation for the new manifest paths
```

### Step 2: Secure Playback

```
Client app:
1. User clicks "Play" on title #12345
2. App calls POST /api/playback/12345 (with JWT Bearer token)
3. API Gateway → Lambda (playback-authorizer):
   a. Verify JWT (Cognito)
   b. Check DynamoDB: does user have active subscription?
   c. Check DynamoDB: is title in user's region's licensed content?
   d. Generate CloudFront Signed URL (valid for 4 hours, IP-locked)
   e. Return: { "manifest_url": "https://cdn.streamvault.com/hls/12345/master.m3u8?Policy=...&Signature=...&Key-Pair-Id=..." }
4. Client player (Video.js / Shaka Player) loads master.m3u8
5. Player picks rendition based on network speed (ABR — Adaptive Bitrate)
6. Player requests .ts segments — each request validated by CloudFront signed URL
```

---

## 4. AWS Services — Chosen and Why

### Video Processing

| Service | Why Chosen | Alternative | Tradeoff |
|---------|-----------|-------------|----------|
| **AWS Elemental MediaConvert** | Managed video transcoding, HLS/DASH/CMAF output, DRM integration | FFmpeg on EC2 | MediaConvert = pay per minute of video processed, managed; FFmpeg = free but requires EC2 fleet, custom queue management; chose MediaConvert to avoid ops burden |
| **S3 (multipart upload)** | Reliable upload of large raw video files (10GB-100GB) | EFS, Transfer Acceleration | S3 multipart = resume interrupted uploads; Transfer Acceleration = uses CloudFront for upload speed; added Transfer Acceleration for studio partners in Asia |

### Content Delivery

| Service | Why Chosen | Alternative | Tradeoff |
|---------|-----------|-------------|----------|
| **CloudFront** | 450+ PoPs, signed URLs, Origin Shield, Lambda@Edge | Akamai, Cloudflare | CloudFront = native S3 integration, tightest AWS integration; Akamai = better live streaming; chose CloudFront for VOD |
| **CloudFront Origin Shield** | Collapse cache misses into single origin request | No Origin Shield | Without Origin Shield, 450 edge locations all hit S3 simultaneously on a cache miss (thundering herd); Origin Shield = 1 request to S3 regardless of how many edges miss simultaneously |
| **CloudFront Signed URLs** | Per-user, time-limited, IP-restricted content access | S3 Pre-signed URLs, Token auth | CloudFront Signed URLs = validated at edge (faster, cheaper than Lambda); S3 Pre-signed = only protects origin, not edge cache; chose CloudFront Signed for piracy protection at scale |

### Data Layer

| Service | Why Chosen | Alternative | Tradeoff |
|---------|-----------|-------------|----------|
| **DynamoDB** | Content catalog, user entitlements, watch history — all high-read, low-latency patterns | Aurora, RDS | DynamoDB = < 5ms reads at any scale, no connection pool limits; Aurora = better for complex queries; chose DynamoDB for the 50k concurrent users hitting catalog |
| **ElastiCache Redis** | Cache signed URL generation results, trending content, user sessions | DynamoDB DAX | Redis = general cache (any data); DAX = only caches DynamoDB reads; Redis chosen for its flexibility (also caches signed URL tokens) |

---

## 5. Adaptive Bitrate Streaming (ABR) — The Architecture Decision

HLS vs DASH vs CMAF:

| Format | Description | Chosen For |
|--------|-------------|-----------|
| **HLS** | Apple's format, best iOS/Safari support | Primary (95% compatibility) |
| **DASH** | MPEG standard, best Android/Chrome | Secondary rendition |
| **CMAF** | Common Media Application Format — single asset serves HLS+DASH | Future optimization |

**Master Manifest structure (HLS):**
```m3u8
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2"
360p/stream.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,CODECS="avc1.640028,mp4a.40.2"
720p/stream.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
1080p/stream.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=16000000,RESOLUTION=3840x2160,CODECS="hev1.1.6.L153.B0,mp4a.40.2"
4k/stream.m3u8
```

The player starts at 360p, measures download speed, and upgrades renditions automatically. This is what eliminates buffering on variable connections.

---

## 6. Content Protection — Signed URL Architecture

### Why Signed URLs Instead of Token Auth

```
Without Signed URLs:                With Signed URLs:
User shares URL in forum            URL is:
→ Anyone can stream for free         - IP-locked (can't share to another machine)
→ Piracy                            - Expires in 4 hours
→ Revenue loss                      - CloudFront validates at edge (no Lambda cost)
                                    → URL is useless to anyone else
```

### Key Rotation Strategy

CloudFront Signed URLs use RSA key pairs:
```
CloudFront Key Pair (2048-bit RSA):
  - Private key: stored in Secrets Manager, rotated every 90 days
  - Public key: uploaded to CloudFront key group
  - Key-Pair-Id: embedded in signed URL
  - Grace period: keep old public key active for 4 hours after rotation (for in-flight sessions)
```

---

## 7. Scaling Strategy

### Concurrent Stream Calculation

```
50,000 concurrent streams
× avg segment size: 4MB (per 6-second HLS segment)
× requests per 6 seconds: 50,000
= 33,333 requests/second to CloudFront

CloudFront can handle millions of req/sec — this is well within limits.
S3 origin: with Origin Shield, only cache misses hit S3.
  Cache hit rate target: 95%
  S3 requests: 50,000 × 5% = 2,500 req/sec to S3 (well within S3 limits)
```

### API Layer Scaling

```
API Gateway (signed URL generation):
  Each stream start = 1 API call
  50,000 simultaneous starts (worst case) = 50,000 req/sec
  API Gateway burst: 10,000 default (request increase to 50,000)
  Lambda concurrency: 1,000 default (set reserved=2,000 for playback-authorizer)

Redis cache for signed URLs:
  Same user replaying = serve cached signed URL (60s TTL)
  Reduces Lambda invocations by ~40% during heavy traffic
```

### CloudFront Cache Optimization

```
Cache behavior for HLS segments:
  TTL: 1 year (segments are immutable — content never changes)
  Query string caching: exclude (signed URL params don't affect cache key)
  
Cache behavior for master manifest:
  TTL: 60 seconds (allows quality updates without full invalidation)

Cache behavior for API responses:
  TTL: 0 (never cache — each request generates unique signed URL)
```

---

## 8. Security Model

### Content Security — Three Layers

```
Layer 1: Network
  - S3 bucket is private — NO public access
  - Only CloudFront can access S3 (via Origin Access Control)
  - Direct S3 URLs return 403

Layer 2: CloudFront Edge
  - Signed URL required for every request (validated cryptographically at edge)
  - IP-locked: URL stolen by different IP = 403
  - Time-limited: 4-hour expiry window

Layer 3: Application
  - JWT validation in Lambda before generating signed URL
  - Entitlement check: user's subscription must be active
  - Geographic restriction: title must be licensed in user's country
  - Concurrent stream limit: 3 streams per account (Redis counter)
```

### Concurrent Stream Limit Implementation

```python
def check_concurrent_streams(user_id: str, redis_client) -> bool:
    key = f"streams:{user_id}"
    current = redis_client.get(key)
    if current and int(current) >= 3:
        return False  # Reject: already at 3 concurrent streams
    
    # Atomic increment with TTL (4h = stream session duration)
    pipe = redis_client.pipeline()
    pipe.incr(key)
    pipe.expire(key, 14400)
    pipe.execute()
    return True
```

---

## 9. Cost Analysis

### Monthly Cost Estimate (500K subscribers, 50K peak concurrent)

| Service | Usage Basis | Monthly Cost |
|---------|------------|-------------|
| MediaConvert | 1,000 hours of video transcoded (new titles) | ~$1,800 |
| S3 storage | 500TB processed video | ~$11,500 |
| S3 requests | 100M requests | ~$400 |
| CloudFront | 500TB egress (50K streams × 2hrs avg × 5GB avg) | ~$42,500 |
| CloudFront requests | 5B HTTP requests | ~$2,000 |
| API Gateway | 10M signed URL generations | ~$35 |
| Lambda | 10M invocations | ~$20 |
| DynamoDB | 50M reads/day | ~$150 |
| ElastiCache | cache.r6g.large × 2 | ~$185 |
| **Total** | | **~$58,590/month** |

### Cost Optimization Decisions

1. **CloudFront cache hit rate is the #1 lever.** Moving cache hit from 85% → 95% saves $8,500/month on egress.
2. **S3 Intelligent Tiering:** Videos not played in 60 days move to Standard-IA (saves 45% on storage).
3. **MediaConvert Reserved Pricing:** If transcoding > 5,000 hours/month, buy reserved capacity (saves 30%).
4. **CloudFront Price Class:** Use `PriceClass_200` (excludes South America edge locations — serve Brazil from US-East instead, save 15% on distribution cost). Reassess when Brazil traffic exceeds 10% of total.
5. **HLS segment size:** Larger segments (10s vs 6s) = fewer S3 requests = lower API cost, but longer initial buffer time. Chose 6s for playback responsiveness.

---

## 10. Failure Modes and Handling

| Failure | User Impact | Architecture Response |
|---------|------------|----------------------|
| Single edge location fails | Users near that PoP see increased latency | Route 53 health checks detect; CloudFront automatically routes to next-nearest PoP |
| Origin S3 unavailable | Cache misses fail (new viewers) | Cached viewers unaffected; Origin Shield buffers retry attempts; stale-while-revalidate TTL serves cached content for up to 24 hours |
| MediaConvert service disruption | New titles not available | SQS queue holds ingest jobs; retries with exponential backoff; new titles delayed, existing library unaffected |
| Lambda (playback-authorizer) cold start | 500-800ms delay on first stream start | Provisioned concurrency for peak hours (6PM-midnight); acceptable for playback initiation (not segment delivery) |
| Redis session store fails | Concurrent stream limit not enforced, signed URL cache miss | DynamoDB fallback for entitlements; signed URLs generated fresh from Lambda (higher cost, acceptable degradation) |
| S3 bucket accidentally made public | Content exposed without DRM | AWS Config rule `s3-bucket-public-read-prohibited` alerts immediately; Macie scans for sensitive content exposure |

---

## 11. Architecture Diagram Layout

For draw.io or Excalidraw:

**Top row (ingest):** Studio → S3 raw → Lambda → MediaConvert → S3 processed
**Middle (delivery):** CloudFront (full width, showing multiple edge locations icons) ← Origin Shield ← S3 processed
**Right side (auth flow):** User → Route 53 → API Gateway → Lambda → DynamoDB → Return signed URL
**Bottom (data):** DynamoDB + ElastiCache side-by-side
**Color:** Orange = S3/storage, Blue = CloudFront/CDN, Purple = Lambda/compute, Green = user/external

---

## Terraform Structure

```
terraform/
├── variables.tf            # Region, content TTLs, concurrent stream limit, rendition list
├── s3_video.tf             # Raw ingest bucket, processed video bucket, access policies
├── mediaconvert.tf         # MediaConvert queue, job template, IAM role
├── cloudfront.tf           # Distribution, Origin Shield, OAC, signed URL key group, cache policies
├── lambda.tf               # Ingest orchestrator, playback authorizer, CloudFront key rotation
├── api_gateway.tf          # Playback API, Cognito authorizer, throttling
├── dynamodb.tf             # Content catalog table, user entitlements table, watch history
├── elasticache.tf          # Redis cluster for sessions, signed URL cache, concurrent stream counter
├── cognito.tf              # User pool for subscribers, social login federation
├── iam.tf                  # MediaConvert role, Lambda execution roles, CloudFront OAC
├── monitoring.tf           # CloudFront real-time logs, playback error alarms, CDN hit rate alarm
└── outputs.tf              # CloudFront domain, API endpoint, S3 bucket names
```

---

## Interview Talking Points

**Q: How does CloudFront Origin Shield work and why use it?**  
Without Origin Shield, all 450+ CloudFront edge locations independently request content from S3 when they don't have it cached. If 100 edge locations simultaneously cache-miss on the same segment, S3 gets 100 requests. Origin Shield adds a single intermediary PoP — all 450 edges route cache misses through Origin Shield, and Origin Shield makes only 1 request to S3. This reduces S3 GET costs by up to 90% and protects S3 from thundering herd during popular new title releases.

**Q: Why use CloudFront Signed URLs instead of S3 pre-signed URLs for video?**  
S3 pre-signed URLs bypass CloudFront entirely — a user with the URL hits S3 directly, which defeats the CDN. CloudFront Signed URLs are validated at the edge before the request even reaches S3, so content is served from CloudFront's cache (fast, cheap) with cryptographic access control. For a 2-hour movie: 1,200 HLS segment requests × validated at edge = $0 additional compute cost vs Lambda validation.

**Q: How do you prevent one account from sharing their login for 50 simultaneous streams?**  
Three mechanisms: (1) Redis atomic counter per user_id, capped at 3 concurrent streams — incremented at stream start, decremented at stream end or after 4-hour TTL; (2) Signed URLs are IP-locked — sharing the URL to a different device fails; (3) CloudFront Geo-restriction can enforce that a US subscription's signed URL only works from US IP ranges. These combined make credential sharing technically possible but practically limited to one household.

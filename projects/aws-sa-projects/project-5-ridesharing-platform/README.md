# Project 5: Real-Time Ride-Sharing & Location Tracking Platform

> **Role Focus:** AWS Solutions Architect
> **Scenario:** Transportation / Marketplace Startup
> **Complexity:** Advanced
> **New Services:** API Gateway WebSocket, Kinesis Data Streams, OpenSearch, SNS/Pinpoint, AppSync

---

## 1. Real-World Problem

**QuickRide** is a transportation startup competing with Uber and Lyft in 3 US metro areas.
Their backend needs to handle:

- Drivers sending GPS location every **5 seconds**
- Riders requesting a trip and being matched to the **nearest available driver** in < 2 seconds
- **Surge pricing** that recalculates every 60 seconds based on supply/demand
- **Push notifications** when a driver accepts a trip
- **Payment processing** that must never block the ride experience
- Peak load: **10,000 concurrent drivers** + **50,000 concurrent riders** on Friday night

| Requirement | Target |
|---|---|
| Driver location update latency | < 500ms end-to-end |
| Driver-to-rider match time | < 2 seconds |
| Concurrent WebSocket connections | 60,000 |
| Trip creation API | 99.99% availability |
| Payment processing | Async, eventual (never blocks ride) |
| Push notification delivery | < 5 seconds |
| Data retention (trips) | 7 years (legal) |

---

## 2. Architecture Overview

```
  DRIVERS (Mobile App)               RIDERS (Mobile App)
       │                                    │
       │ WebSocket (location updates)       │ REST (trip requests)
       ▼                                    ▼
  ┌────────────────────────────────────────────────────────────┐
  │              API Gateway                                    │
  │   WebSocket API          REST API (v1)                     │
  │   ($connect/$disconnect) (/trips /drivers /pricing)        │
  └──────┬───────────────────────────┬───────────────────────-─┘
         │                           │
         ▼                           ▼
  ┌──────────────┐          ┌────────────────────┐
  │   Lambda     │          │   Lambda           │
  │  (location   │          │  (trip-manager)    │
  │   handler)   │          │                    │
  └──────┬───────┘          └────────┬───────────┘
         │                           │
         ▼                           ▼
  ┌──────────────┐          ┌────────────────────┐
  │   Kinesis    │          │   DynamoDB         │
  │ Data Streams │          │  (trips, users,    │
  │ (10 shards)  │          │   driver state)    │
  └──────┬───────┘          └────────────────────┘
         │
         ▼
  ┌──────────────┐    ┌──────────────────────┐
  │   Lambda     │───▶│  ElastiCache Redis   │
  │  (location   │    │  driver:loc:{id}     │
  │   consumer)  │    │  surge:{zone}        │
  └──────┬───────┘    └──────────────────────┘
         │
         ▼
  ┌──────────────────────┐
  │   OpenSearch         │
  │  (geo_point index)   │
  │  - Driver locations  │
  │  - Find nearest 5    │
  └──────┬───────────────┘
         │
         ▼
  ┌──────────────┐    ┌──────────────────────┐
  │   Lambda     │───▶│   SQS                │
  │  (matching   │    │  (payment queue)     │
  │   engine)    │    │  (notification queue)│
  └──────────────┘    └──────────────────────┘
                              │
                   ┌──────────▼──────────┐
                   │  SNS / Pinpoint     │
                   │  (push to iOS/Android)│
                   └─────────────────────┘
```

---

## 3. AWS Services — Chosen and Why

### Real-Time Communication

| Service | Why Chosen | Alternative | Tradeoff |
|---|---|---|---|
| **API Gateway WebSocket** | Persistent bidirectional connections, AWS-managed, scales automatically | Self-hosted Socket.io on EC2 | WebSocket API = $1/million connection-minutes, zero server management; Socket.io = more features (rooms, namespacing) but requires EC2 fleet |
| **Kinesis Data Streams** | Buffer 10,000 driver location updates/sec without losing data | SQS, direct Lambda invoke | Kinesis = ordered within shard, replay-capable, fan-out to multiple consumers; SQS = simpler but no ordering guarantee; Kinesis chosen for ordered location history |

### Location & Matching

| Service | Why Chosen | Alternative | Tradeoff |
|---|---|---|---|
| **OpenSearch (Elasticsearch)** | Native geo_point field, 100ms geo-distance queries, "find nearest 5 drivers" in one query | DynamoDB + manual geo math, PostGIS | OpenSearch = purpose-built for geo search; DynamoDB has no geo query support; PostGIS requires Aurora; OpenSearch wins for geo matching |
| **ElastiCache Redis** | Sub-millisecond driver location cache (GEOADD/GEORADIUS commands), surge pricing cache | DynamoDB DAX | Redis GEORADIUS = native geospatial commands; DynamoDB has no geo support; Redis chosen for real-time driver position cache (5s TTL) |

### Async Processing

| Service | Why Chosen | Alternative | Tradeoff |
|---|---|---|---|
| **SQS FIFO** | Payment jobs processed exactly-once, ordered per trip | Standard SQS, EventBridge | FIFO = deduplication prevents double charges; Standard = higher throughput but risk of duplicate payment; FIFO required for payments |
| **SNS + Pinpoint** | Push notifications to iOS (APNs) and Android (FCM) | Firebase directly, SES | SNS = native APNs/FCM integration; Pinpoint adds analytics (open rate, delivery rate); chose SNS+Pinpoint for delivery analytics |

---

## 4. Data Model Design

### DynamoDB — Trip Table (Single Table Design)

```
PK                  SK                      Attributes
───────────────────────────────────────────────────────────────
TRIP#t1             META                    status, rider_id, driver_id, pickup, dropoff, fare, created_at
TRIP#t1             TIMELINE#01_REQUESTED   timestamp, event=trip_requested
TRIP#t1             TIMELINE#02_MATCHED     timestamp, driver_id, eta_seconds
TRIP#t1             TIMELINE#03_ARRIVED     timestamp
TRIP#t1             TIMELINE#04_STARTED     timestamp, start_odometer
TRIP#t1             TIMELINE#05_COMPLETED   timestamp, distance_miles, final_fare
DRIVER#d1           STATE                   status (available/busy/offline), vehicle, rating, current_zone
DRIVER#d1           STATS#2024-01           trips_completed, earnings, hours_online
RIDER#r1            PROFILE                 name, email, default_payment_method_id
RIDER#r1            TRIP_HISTORY#t1         fare, rating_given, pickup, dropoff
ZONE#downtown       SURGE                   multiplier, updated_at, demand_count, supply_count
```

**Why single table?**
All trip lifecycle data is co-located under `TRIP#{id}`. One DynamoDB query retrieves the full trip timeline. No JOINs needed.

### Redis — Real-Time Location Store

```
Key: driver:loc:{driver_id}
Value: Hash { lat, lng, heading, speed, updated_at }
TTL: 30 seconds (driver considered offline if no update in 30s)

Key: surge:zone:{zone_id}
Value: Float (e.g., 1.8 = 1.8x multiplier)
TTL: 60 seconds (recalculates every minute)

Key: ws:connection:{connection_id}
Value: String (driver_id or rider_id)
TTL: 7200 seconds (2-hour max session)
```

### OpenSearch — Driver Location Index

```json
{
  "mappings": {
    "properties": {
      "driver_id":   { "type": "keyword" },
      "location":    { "type": "geo_point" },
      "status":      { "type": "keyword" },
      "vehicle_type":{ "type": "keyword" },
      "rating":      { "type": "float" },
      "updated_at":  { "type": "date" }
    }
  }
}
```

Matching query — find 5 nearest available drivers within 5km:
```json
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "available" } },
        { "geo_distance": {
            "distance": "5km",
            "location": { "lat": 40.7128, "lon": -74.0060 }
        }}
      ]
    }
  },
  "sort": [{ "_geo_distance": { "location": { "lat": 40.7128, "lon": -74.0060 }, "order": "asc" } }],
  "size": 5
}
```

---

## 5. Step-by-Step Implementation Guide

> Follow these phases in order. Each phase is independently testable before moving to the next.

---

### Phase 1 — Foundation: VPC & Networking

**What you're building:** A VPC with public subnets (API Gateway endpoints) and private subnets (Lambda, Redis, OpenSearch, Kinesis consumers).

**Why this matters:** Lambda functions in a VPC can talk to ElastiCache and OpenSearch privately. Kinesis and DynamoDB are accessed via VPC endpoints (no NAT cost).

**Steps:**

```bash
# 1. Initialize Terraform
cd projects/project-5-ridesharing-platform/terraform
terraform init

# 2. Create the VPC (review before applying)
terraform plan -target=aws_vpc.main
terraform apply -target=aws_vpc.main

# 3. Verify VPC created
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=quickride-production-vpc"
```

**What to check:** VPC has `enable_dns_hostnames=true` — required for Lambda to resolve private DNS names of ElastiCache and OpenSearch.

---

### Phase 2 — Authentication: Cognito for Drivers and Riders

**What you're building:** Two separate Cognito User Pools — one for riders, one for drivers. Drivers have extra attributes (vehicle type, license plate, background check status).

**Why separate pools?**
Riders and drivers have completely different attributes, verification flows, and token claims. A driver JWT needs `custom:driver_id` and `custom:vehicle_type` claims. Mixing them in one pool creates messy attribute management.

**Steps:**

```bash
# Apply Cognito resources
terraform apply -target=aws_cognito_user_pool.riders
terraform apply -target=aws_cognito_user_pool.drivers

# Verify pools created
aws cognito-idp list-user-pools --max-results 10

# Create a test rider account
aws cognito-idp sign-up \
  --client-id $(terraform output -raw rider_cognito_client_id) \
  --username test-rider@quickride.com \
  --password "TestPass123!" \
  --user-attributes Name=name,Value="Test Rider"

# Confirm the test account (skip email in dev)
aws cognito-idp admin-confirm-sign-up \
  --user-pool-id $(terraform output -raw rider_user_pool_id) \
  --username test-rider@quickride.com
```

**What to check:** JWT tokens from the rider pool should contain `custom:rider_id`. JWT tokens from the driver pool should contain `custom:driver_id` and `custom:background_check_status`.

---

### Phase 3 — Real-Time Location: WebSocket API + Kinesis

**What you're building:** Drivers connect to a WebSocket API and stream GPS coordinates every 5 seconds. Coordinates flow into Kinesis for ordered, buffered processing.

**Why WebSocket + Kinesis (not just WebSocket → Lambda directly)?**
At 10,000 drivers × 1 update/5s = 2,000 location updates/second. Direct Lambda invocation at 2,000/sec is fine, but Kinesis gives you:
1. **Replay:** If the location consumer Lambda fails, Kinesis replays from the last checkpoint
2. **Order:** Location updates stay ordered per driver (same shard key = same shard)
3. **Fan-out:** Multiple consumers can read the same stream (matching engine + analytics)

**Steps:**

```bash
# Deploy WebSocket API and Kinesis stream
terraform apply -target=aws_apigatewayv2_api.driver_ws
terraform apply -target=aws_kinesis_stream.driver_locations

# Get the WebSocket endpoint
WS_URL=$(terraform output -raw websocket_endpoint)
echo "WebSocket URL: $WS_URL"
# e.g. wss://abc123.execute-api.us-east-1.amazonaws.com/production

# Test WebSocket connection (install wscat: npm install -g wscat)
wscat -c "$WS_URL" -H "Authorization: Bearer $DRIVER_JWT"

# Send a location update (in wscat session)
{"action":"updateLocation","lat":40.7128,"lng":-74.0060,"heading":270,"speed":35}

# Verify message appeared in Kinesis
aws kinesis get-shard-iterator \
  --stream-name quickride-production-driver-locations \
  --shard-id shardId-000000000000 \
  --shard-iterator-type TRIM_HORIZON \
  --query ShardIterator --output text | xargs -I{} \
  aws kinesis get-records --shard-iterator {}
```

**What to check:** Each Kinesis record's partition key should be the `driver_id` — this ensures all updates from one driver land in the same shard (ordered processing).

---

### Phase 4 — Location Indexing: Kinesis → Lambda → Redis + OpenSearch

**What you're building:** A Lambda function consumes from Kinesis, writes each driver's location to Redis (for instant lookup), and upserts into OpenSearch (for geo-radius matching).

**The two-store pattern explained:**

```
Redis (cache)          OpenSearch (search)
─────────────          ──────────────────
Sub-ms reads           100ms geo queries
Key-value only         Full geo-distance search
30s TTL                Persistent, queryable
"Where is driver X?"   "Find 5 drivers near location Y"
```

**Steps:**

```bash
# Deploy OpenSearch domain (takes ~15 minutes to provision)
terraform apply -target=aws_opensearch_domain.main
# Watch domain status:
aws opensearch describe-domain \
  --domain-name quickride-production \
  --query "DomainStatus.Processing"
# Wait until "false" (domain is ready)

# Deploy ElastiCache Redis
terraform apply -target=aws_elasticache_replication_group.main

# Deploy location consumer Lambda
terraform apply -target=aws_lambda_function.location_consumer
terraform apply -target=aws_lambda_event_source_mapping.kinesis_to_consumer

# Verify the Lambda trigger is enabled
aws lambda list-event-source-mappings \
  --function-name quickride-production-location-consumer \
  --query "EventSourceMappings[0].State"
# Should return "Enabled"

# Check OpenSearch has the driver index
curl -X GET "https://$(terraform output -raw opensearch_endpoint)/drivers/_count" \
  --aws-sigv4 "aws:amz:us-east-1:es" \
  --user "$(aws sts get-caller-identity --query Arn --output text):"
```

**What to check:** After sending location updates in Phase 3, query OpenSearch and verify driver documents are being upserted with `geo_point` coordinates.

---

### Phase 5 — Matching Engine: Finding the Nearest Driver

**What you're building:** When a rider requests a trip, a Lambda function queries OpenSearch for the 5 nearest available drivers, calculates ETAs, and sends a push notification to the best match.

**The matching algorithm:**

```python
def match_driver(pickup_lat, pickup_lng, vehicle_type, rider_id):
    # 1. Query OpenSearch for nearest 5 available drivers
    candidates = opensearch_geo_query(
        lat=pickup_lat, lng=pickup_lng,
        distance="5km",
        filters={"status": "available", "vehicle_type": vehicle_type},
        size=5
    )

    if not candidates:
        return None  # No drivers available — trigger surge pricing

    # 2. For each candidate, get real-time location from Redis
    #    (OpenSearch may be 5-10 seconds stale; Redis is < 500ms fresh)
    for driver in candidates:
        fresh_location = redis.hgetall(f"driver:loc:{driver['driver_id']}")
        driver['fresh_lat'] = fresh_location['lat']
        driver['fresh_lng'] = fresh_location['lng']
        driver['eta_seconds'] = estimate_eta(fresh_location, pickup_lat, pickup_lng)

    # 3. Score drivers: lower ETA + higher rating wins
    best_match = min(candidates, key=lambda d: d['eta_seconds'] * (1 / d['rating']))

    # 4. Atomically mark driver as busy (prevent double-booking)
    #    Use DynamoDB conditional write: only succeeds if status == "available"
    success = dynamodb_conditional_update(
        pk=f"DRIVER#{best_match['driver_id']}",
        sk="STATE",
        condition="status = :available",
        update="SET status = :busy, current_trip = :trip_id",
        values={":available": "available", ":busy": "busy", ":trip_id": trip_id}
    )

    if not success:
        # Driver just got booked by another rider — try next candidate
        return match_driver(pickup_lat, pickup_lng, vehicle_type, rider_id)

    return best_match
```

**Steps:**

```bash
# Deploy matching engine Lambda
terraform apply -target=aws_lambda_function.matching_engine

# Test trip request via REST API
RIDER_JWT="..." # from Phase 2 test
API_ENDPOINT=$(terraform output -raw rest_api_endpoint)

curl -X POST "$API_ENDPOINT/trips" \
  -H "Authorization: Bearer $RIDER_JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "pickup": {"lat": 40.7128, "lng": -74.0060, "address": "1 World Trade Center"},
    "dropoff": {"lat": 40.7580, "lng": -73.9855, "address": "Times Square"},
    "vehicle_type": "standard"
  }'

# Expected response:
# {
#   "trip_id": "t_abc123",
#   "status": "MATCHING",
#   "message": "Finding your driver..."
# }

# Check DynamoDB for the trip record
aws dynamodb get-item \
  --table-name quickride-production-trips \
  --key '{"PK":{"S":"TRIP#t_abc123"},"SK":{"S":"META"}}'
```

**What to check:** The DynamoDB conditional write pattern prevents two riders from booking the same driver simultaneously. This is your race condition protection without distributed locks.

---

### Phase 6 — Surge Pricing: Supply vs Demand Algorithm

**What you're building:** A CloudWatch Events scheduled Lambda that runs every 60 seconds, counts available drivers vs active trip requests per zone, and writes surge multipliers to Redis.

**The surge pricing formula:**

```python
def calculate_surge(zone_id: str) -> float:
    # Count available drivers in this zone (from OpenSearch)
    available_drivers = opensearch_count(
        filter={"status": "available", "zone": zone_id}
    )

    # Count pending trip requests in last 5 minutes (from DynamoDB)
    pending_requests = dynamodb_query(
        pk=f"ZONE#{zone_id}",
        sk_begins_with="REQUEST#",
        filter_expression="created_at > :five_min_ago"
    )

    if available_drivers == 0:
        return 3.0  # Maximum surge: no drivers at all

    demand_ratio = len(pending_requests) / available_drivers

    # Surge tiers:
    if demand_ratio < 0.5:   return 1.0   # Normal pricing
    elif demand_ratio < 1.0: return 1.2   # Mild surge
    elif demand_ratio < 1.5: return 1.5   # Moderate surge
    elif demand_ratio < 2.0: return 1.8   # High surge
    else:                    return 2.5   # Very high surge

    # Write to Redis with 60s TTL
    redis.setex(f"surge:zone:{zone_id}", 60, surge_multiplier)
```

**Steps:**

```bash
# Deploy surge pricing Lambda and CloudWatch scheduler
terraform apply -target=aws_lambda_function.surge_calculator
terraform apply -target=aws_cloudwatch_event_rule.surge_schedule

# Manually trigger to verify
aws lambda invoke \
  --function-name quickride-production-surge-calculator \
  --payload '{}' \
  /tmp/surge-output.json && cat /tmp/surge-output.json

# Check Redis for zone surge prices
# (requires redis-cli on a bastion or Lambda test)
# KEYS surge:zone:*
# GET surge:zone:downtown
```

**What to check:** Verify Redis keys have 60-second TTL (`TTL surge:zone:downtown` returns ~60). If the key expires without a new calculation, the application defaults to 1.0 (no surge) — a safe fallback.

---

### Phase 7 — Payments: Async Processing via SQS

**What you're building:** When a trip completes, a Lambda publishes a payment job to SQS FIFO. A payment processor Lambda reads from SQS, calls Stripe's API, and updates DynamoDB with the charge result. This is intentionally asynchronous — the rider's app shows "trip complete" immediately without waiting for payment.

**Why async payments?**
Stripe API calls take 200-800ms. Making the rider wait for payment confirmation before showing "Trip Complete" degrades the experience. SQS decouples payment from trip completion — if Stripe is slow, the SQS message waits and retries automatically.

**Steps:**

```bash
# Deploy SQS queue and payment processor Lambda
terraform apply -target=aws_sqs_queue.payments
terraform apply -target=aws_lambda_function.payment_processor

# Simulate a trip completion (publishes to SQS)
aws lambda invoke \
  --function-name quickride-production-trip-manager \
  --payload '{
    "action": "complete_trip",
    "trip_id": "t_abc123",
    "end_lat": 40.7580,
    "end_lng": -73.9855,
    "distance_miles": 3.2
  }' /tmp/output.json

# Check SQS queue depth (should see 1 message)
aws sqs get-queue-attributes \
  --queue-url $(terraform output -raw payment_queue_url) \
  --attribute-names ApproximateNumberOfMessages

# Check DLQ (should be 0 — no failed payments)
aws sqs get-queue-attributes \
  --queue-url $(terraform output -raw payment_dlq_url) \
  --attribute-names ApproximateNumberOfMessages
```

**What to check:** SQS FIFO deduplication — if the trip-complete event fires twice (network retry), the FIFO queue's `MessageDeduplicationId` (set to `trip_id`) prevents the payment Lambda from processing the charge twice. This is your double-charge protection.

---

### Phase 8 — Push Notifications: SNS + Pinpoint

**What you're building:** When a driver is matched, the rider gets a push notification ("Your driver is 3 minutes away"). When a driver accepts, they get the pickup address. These go through SNS to APNs (iOS) and FCM (Android).

**Steps:**

```bash
# Deploy SNS platform applications
terraform apply -target=aws_sns_platform_application.ios
terraform apply -target=aws_sns_platform_application.android

# Register a test device (in production, mobile app does this on login)
ENDPOINT_ARN=$(aws sns create-platform-endpoint \
  --platform-application-arn $(terraform output -raw ios_platform_arn) \
  --token "DEVICE_PUSH_TOKEN_HERE" \
  --query EndpointArn --output text)

# Send a test notification
aws sns publish \
  --target-arn "$ENDPOINT_ARN" \
  --message-structure json \
  --message '{
    "APNS": "{\"aps\":{\"alert\":{\"title\":\"Driver Found!\",\"body\":\"Ahmed is 3 min away in a blue Toyota Camry\"},\"sound\":\"default\",\"badge\":1}}"
  }'
```

**What to check:** SNS delivery status logging (enable `--attributes '{"DeliveryStatusSuccessSamplingRate":"100"}'`) to see APNs/FCM delivery confirmations in CloudWatch.

---

### Phase 9 — Monitoring: CloudWatch Dashboard

**Key metrics to track for this architecture:**

| Metric | Alarm Threshold | Why Critical |
|---|---|---|
| `WebSocketConnections` (API GW) | > 55,000 | Approaching 60k limit — scale plan needed |
| `KinesisIteratorAge` (stream) | > 10,000ms | Consumer Lambda falling behind — location data going stale |
| `OpenSearchClusterStatus` | Not Green | Red/Yellow = geo queries degrade — matching breaks |
| `matching_engine Errors` | > 1% | Failed matches = stranded riders |
| `SQS payment DLQ depth` | > 0 | Any failed payment needs immediate attention |
| `Redis hit rate` | < 80% | Too many cache misses — driver location lookups hitting OpenSearch |

```bash
# Deploy monitoring resources
terraform apply -target=aws_cloudwatch_dashboard.main
terraform apply -target=aws_cloudwatch_metric_alarm.kinesis_iterator_age
terraform apply -target=aws_cloudwatch_metric_alarm.dlq_depth

# View dashboard URL
echo "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=quickride-production"
```

---

## 6. Security Architecture

### Network Security

```
Internet → API Gateway (managed, no VPC needed)
         → Lambda (in VPC private subnets)
         → ElastiCache (private subnet, SG: Redis from Lambda SG only)
         → OpenSearch (private subnet, SG: HTTPS from Lambda SG only)
         → DynamoDB (via VPC endpoint — no internet, no NAT cost)
         → Kinesis (via VPC endpoint — no internet, no NAT cost)
```

### IAM Design

```
WebSocket Lambda role:
  - kinesis:PutRecord on driver-locations stream
  - dynamodb:PutItem on trips table (connection tracking)
  - NO access to payment data

Location Consumer Lambda role:
  - kinesis:GetRecords, GetShardIterator (read-only)
  - elasticache: (via VPC, no IAM — auth via Redis AUTH token)
  - es:ESHttpPost, ESHttpPut on OpenSearch domain

Matching Engine Lambda role:
  - dynamodb:UpdateItem (conditional write for driver status)
  - es:ESHttpGet (geo query only)
  - sns:Publish (notification only)
  - NO payment access

Payment Processor Lambda role:
  - sqs:ReceiveMessage, DeleteMessage on payment queue only
  - dynamodb:UpdateItem on trips table (write payment status)
  - secretsmanager:GetSecretValue for Stripe API key
  - NO access to location data, NO access to Kinesis
```

**Principle:** Each Lambda has the minimum permissions for its exact job. The payment Lambda cannot read location data. The location Lambda cannot touch payment data. Blast radius of a compromised Lambda is isolated.

---

## 7. Failure Scenarios and Architecture Responses

| Failure | What Happens | Architecture Response |
|---|---|---|
| **Driver WebSocket drops** | Driver location stops updating | Redis TTL expires (30s) → driver marked offline in OpenSearch → excluded from matching |
| **Kinesis consumer Lambda crashes** | Location updates pile up in Kinesis | Kinesis retains data for 24 hours; Lambda auto-retries from last checkpoint; driver data stale but not lost |
| **OpenSearch unavailable** | Matching engine can't find drivers | Fallback: Redis GEORADIUS command (Redis has native geo search) for degraded matching |
| **Redis unavailable** | Location cache + surge pricing down | Matching engine falls back to OpenSearch directly (slower, ~200ms vs 10ms); surge pricing defaults to 1.0 |
| **SQS payment DLQ gets messages** | Some payments failed to process | Alert fires immediately; ops team investigates; messages replay after fix; idempotency key = trip_id prevents double charge |
| **Full AZ outage** | ~33% of infrastructure down | Lambda auto-routes to other AZs; DynamoDB multi-AZ by default; OpenSearch multi-AZ; Redis multi-AZ with auto-failover |

---

## 8. CAP Theorem Position

This system makes **different consistency choices per subsystem:**

| Subsystem | Choice | Why |
|---|---|---|
| **Driver availability (DynamoDB conditional write)** | CP — Consistent | Must prevent double-booking. Two riders cannot get the same driver. |
| **Location updates (Kinesis + Redis)** | AP — Available | Slightly stale location (5-10s) is acceptable. Availability > perfect freshness. |
| **Surge pricing (Redis)** | AP — Available | If surge cache expires, default to 1.0. Availability > accuracy for pricing. |
| **Trip history (DynamoDB)** | CP — Consistent | Payment and legal records must be consistent and durable. |

---

## 9. Cost Estimate

| Service | Usage | Monthly Cost |
|---|---|---|
| API Gateway WebSocket | 60K connections × 2hr avg × 30 days | ~$22 |
| Kinesis Data Streams | 10 shards × 730 hrs | ~$146 |
| Lambda (all functions) | 500M invocations | ~$100 |
| OpenSearch (r6g.large.search × 2) | Multi-AZ cluster | ~$290 |
| ElastiCache Redis (r6g.large × 2) | Multi-AZ | ~$185 |
| DynamoDB (on-demand) | 500M reads, 100M writes | ~$310 |
| SNS push notifications | 50M notifications | ~$20 |
| SQS FIFO (payments) | 10M messages | ~$10 |
| **Total** | | **~$1,083/month** |

**Cost vs self-managed:** Running this on EC2 (Socket.io, self-managed Elasticsearch, Redis) would cost ~$2,400/month and require a dedicated DevOps team. AWS managed services reduce operational overhead by ~70%.

---

## 10. Scalability Strategy

### WebSocket Connection Scaling

```
API Gateway WebSocket: 10,000 connections/region (soft limit)
Request increase to: 100,000 for production

Connection routing: API Gateway → Lambda (stateless)
Connection state: stored in Redis (ws:connection:{id} → driver_id)
Horizontal scale: Lambda scales automatically — no action needed
```

### Kinesis Shard Scaling

```
Current: 10 shards × 1,000 records/sec = 10,000 records/sec capacity
At 10,000 drivers × 1 update/5sec = 2,000 updates/sec (20% utilization)

Scale-out trigger: CloudWatch IteratorAgeMilliseconds > 5000ms
Action: aws kinesis update-shard-count --stream-name driver-locations --target-shard-count 20
```

### OpenSearch Node Scaling

```
Current: 2 × r6g.large (2 vCPU, 16GB) — handles ~5,000 geo queries/sec
Scale up path: r6g.xlarge (4 vCPU, 32GB) for 10,000 geo queries/sec
Scale out path: increase replica count (each replica can serve reads)
```

---

## 11. Architecture Diagram Layout

For draw.io or Excalidraw:

- **Top row:** Driver app (left) → WebSocket API, Rider app (right) → REST API
- **Middle layer:** Lambda functions (location handler, matching engine, surge calculator, payment processor)
- **Data layer:** Kinesis (left), DynamoDB (center), Redis + OpenSearch (right)
- **Bottom:** SQS → Payment Lambda, SNS → Mobile devices
- **Color coding:** Blue = real-time/streaming, Orange = storage, Green = async/queue, Purple = notifications

---

## Terraform Structure

```
terraform/
├── variables.tf          # Region, concurrency limits, Kinesis shard count
├── vpc.tf                # VPC, private subnets, VPC endpoints (DynamoDB, Kinesis)
├── cognito.tf            # Two User Pools (riders, drivers) with custom attributes
├── websocket_api.tf      # API Gateway WebSocket API, routes, Lambda integrations
├── rest_api.tf           # REST API for trip management, Cognito authorizer
├── kinesis.tf            # Data stream, shard configuration, enhanced monitoring
├── opensearch.tf         # Domain, index policy, access policy, VPC config
├── elasticache.tf        # Redis cluster, Multi-AZ, TLS, AUTH token
├── dynamodb.tf           # Single table, GSIs, streams, point-in-time recovery
├── lambda.tf             # All 6 Lambda functions, IAM roles, VPC config
├── sqs.tf                # FIFO payment queue, DLQ, access policy
├── sns.tf                # Platform applications (iOS APNs, Android FCM)
├── monitoring.tf         # CloudWatch dashboard, 8 alarms, SNS alert topic
└── outputs.tf            # WebSocket URL, REST API URL, all resource names
```

---

## Setup Instructions (Full End-to-End)

```bash
# Prerequisites
# - AWS CLI configured (aws configure)
# - Terraform >= 1.5 installed
# - Node.js (for wscat WebSocket testing)
# - jq (for JSON parsing in scripts)

cd projects/project-5-ridesharing-platform/terraform

# Step 1: Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit: alert_email, apns_certificate, fcm_server_key

# Step 2: Initialize
terraform init

# Step 3: Deploy in order (OpenSearch takes longest)
terraform apply -target=aws_vpc.main -auto-approve
terraform apply -target=aws_opensearch_domain.main   # Takes 15 min
terraform apply -target=aws_elasticache_replication_group.main
terraform apply -target=aws_dynamodb_table.main
terraform apply -target=aws_kinesis_stream.driver_locations

# Step 4: Deploy application layer
terraform apply  # Deploys all remaining resources

# Step 5: Get endpoints
terraform output

# Step 6: Run end-to-end test
./scripts/e2e-test.sh
```

---

## Interview Talking Points

**Q: How do you prevent two riders from booking the same driver at the same time?**
DynamoDB conditional writes with optimistic locking. The matching engine writes `status = busy` only if `status = available` — this is an atomic operation in DynamoDB. If two Lambdas race to book the same driver, exactly one succeeds and the other retries with the next candidate. No distributed locks, no transactions overhead.

**Q: Why Kinesis instead of just Lambda processing location updates directly?**
At 10,000 drivers × 12 updates/minute = 120,000 Lambda invocations per minute — fine for Lambda. But Kinesis gives replay capability. If the location consumer Lambda has a bug and crashes, all location updates are preserved in Kinesis for 24 hours and replay from the exact checkpoint when fixed. Direct Lambda invocations at that scale = any processing failure loses the data permanently.

**Q: Why two location stores (Redis AND OpenSearch)?**
Redis answers "Where is driver X right now?" in < 1ms using a key lookup. OpenSearch answers "Which 5 drivers are nearest to this location?" in 100ms using a geo query. Redis has no geo-radius search across all drivers. OpenSearch has no sub-millisecond key lookup. Each tool solves exactly what the other cannot.

**Q: How does this architecture handle a surge in demand like New Year's Eve?**
Four automatic scaling mechanisms: (1) API Gateway WebSocket handles 100K connections with zero configuration, (2) Lambda scales from 0 to 1,000 concurrent executions automatically, (3) Kinesis can add shards in minutes via UpdateShardCount, (4) DynamoDB in PAY_PER_REQUEST mode scales reads/writes instantly. The only component requiring manual scaling is OpenSearch — we'd add nodes the day before a known peak event.

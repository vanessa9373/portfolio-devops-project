# Project 3: Secure FinTech Data Lake & Analytics Platform

> **Role Focus:** AWS Solutions Architect  
> **Scenario:** FinTech / Regulated Industry  
> **Complexity:** Advanced  

---

## 1. Real-World Problem

**ClearPay** is a payments FinTech processing $2B in transactions annually. Their data team has a critical problem: transaction data lives in 6 different systems (payment processor, fraud engine, core banking, risk, CRM, and ledger). Analysts write individual SQL queries against production databases — slowing down live systems and creating data access control nightmares.

**The ask:** Build a centralized data lake that ingests from all 6 systems, provides SQL analytics, enforces row-level and column-level security (masking PII for analysts, full access for compliance), and meets PCI-DSS and SOC 2 requirements.

| Requirement | Target |
|-------------|--------|
| Data sources | 6 upstream systems (batch + streaming) |
| Data volume (daily ingest) | 500GB/day raw → 50GB compressed Parquet |
| Retention | 7 years (regulatory requirement) |
| Query latency | Ad-hoc < 30s, dashboards < 5s |
| Access control | Row-level (by region), column-level (mask PAN, SSN) |
| Compliance | PCI-DSS Level 1, SOC 2 Type II |
| Availability | 99.9% for query access |

---

## 2. Architecture Overview

```
  ┌─────────────────────────────────────────────────────────────┐
  │                    DATA SOURCES                              │
  │  Payment DB  Fraud Engine  Core Banking  CRM  Risk  Ledger  │
  └────────────────────────┬────────────────────────────────────┘
                           │ (Batch nightly + CDC streaming)
             ┌─────────────▼─────────────┐
             │     AWS Glue (ETL)        │
             │  - Extract from sources   │
             │  - Transform to Parquet   │
             │  - Enforce schema         │
             │  - PII detection + mask   │
             └─────────────┬─────────────┘
                           │
  ┌────────────────────────▼────────────────────────────────────┐
  │                   S3 DATA LAKE (3 Zones)                     │
  │                                                             │
  │  Raw Zone          Curated Zone        Aggregated Zone      │
  │  (compressed)      (Parquet, partitioned) (pre-aggregated)  │
  │  s3://raw/         s3://curated/       s3://aggregated/     │
  └──────────┬─────────────────┬───────────────────────────────┘
             │                 │
  ┌──────────▼──────┐  ┌───────▼──────────┐
  │  AWS Glue       │  │  Amazon Redshift  │
  │  Data Catalog   │  │  Serverless       │
  │  (schema reg.)  │  │  (BI dashboards)  │
  └──────────┬──────┘  └───────┬──────────┘
             │                 │
  ┌──────────▼──────────────────▼──────────┐
  │         Amazon Athena                   │
  │  (ad-hoc SQL, pay-per-query)            │
  │  + Lake Formation column masking        │
  └──────────────────────────────────────────┘
             │
  ┌──────────▼──────┐  ┌─────────────────┐
  │  QuickSight     │  │  AWS Macie      │
  │  (dashboards)   │  │  (PII scanner)  │
  └─────────────────┘  └─────────────────┘

  Lake Formation: Row-level + column-level security on all queries
  CloudTrail + Macie: Compliance audit trail
  KMS: Encryption with separate keys per data zone
```

---

## 3. Data Lake Zone Architecture

### Zone Design (Medallion Architecture)

| Zone | S3 Prefix | Format | Who Reads | Retention |
|------|-----------|--------|-----------|-----------|
| **Raw** | `s3://clearpay-lake/raw/` | CSV, JSON (compressed) | Glue ETL only | 7 years |
| **Curated** | `s3://clearpay-lake/curated/` | Parquet, partitioned by date | Athena, Redshift Spectrum | 7 years |
| **Aggregated** | `s3://clearpay-lake/aggregated/` | Parquet (pre-aggregated) | QuickSight, BI tools | 3 years |

### Partition Strategy

```
s3://clearpay-lake/curated/transactions/
  year=2024/
    month=01/
      day=15/
        region=us-east/
          part-00001.parquet
          part-00002.parquet
```

**Why partition by year/month/day/region?**  
Athena scans only partitions matching the WHERE clause. A query for `WHERE date = '2024-01-15' AND region = 'us-east'` scans 1 partition instead of the entire table — reducing query cost by 99%+ and improving speed from minutes to seconds.

---

## 4. AWS Services — Chosen and Why

### Ingestion & ETL

| Service | Why Chosen | Alternative | Tradeoff |
|---------|-----------|-------------|----------|
| **AWS Glue** | Serverless Spark ETL, native AWS integration, Glue Data Catalog | EMR | Glue = fully managed, no cluster management; EMR = more control, cheaper for sustained heavy workloads; chose Glue for operational simplicity |
| **AWS DMS** | Migrate and continuously replicate from RDS/PostgreSQL sources | Glue CDC, Kafka | DMS = purpose-built for DB replication; Kafka = more flexible but requires MSK cluster management |
| **Kinesis Data Firehose** | Real-time streaming ingestion for fraud events | Kinesis Data Streams | Firehose = automatic delivery to S3 without consumer code; Streams = more control, exactly-once; chose Firehose for simplicity |

### Query & Analytics

| Service | Why Chosen | Alternative | Tradeoff |
|---------|-----------|-------------|----------|
| **Amazon Athena** | Serverless SQL on S3, pay per TB scanned, no infrastructure | EMR Spark, Presto | Athena = zero infra, $5/TB; EMR = cheaper at scale (>100TB/day); chose Athena for < 500GB/day volume |
| **Redshift Serverless** | Persistent SQL engine for BI dashboards requiring < 5s response | Redshift provisioned | Serverless = pay per use, no cluster sizing; Provisioned = predictable cost at high query volume; chose Serverless while query patterns are still evolving |
| **AWS Glue Data Catalog** | Central schema registry, version-controlled table definitions | Apache Hive Metastore | Data Catalog = native Athena/Redshift/Glue integration; Hive Metastore = open source but requires infrastructure |

### Security & Governance

| Service | Why Chosen | Alternative | Tradeoff |
|---------|-----------|-------------|----------|
| **AWS Lake Formation** | Column-level security, row-level filters, tag-based access control | S3 bucket policies + IAM alone | Lake Formation = fine-grained per-column masking; S3 policies = coarse bucket-level only; Lake Formation required for PII masking |
| **AWS Macie** | Automated PII discovery and classification in S3 | Manual data classification | Macie = continuous automated scanning; Manual = free but misses unknown PII; Macie required for SOC 2 evidence |
| **AWS KMS** | Separate CMKs per data zone for isolation | S3-managed SSE (SSE-S3) | CMK = audit trail in CloudTrail, key rotation, cross-account sharing; SSE-S3 = simpler but no granular key control; CMK required for PCI-DSS |

---

## 5. Security Architecture — Column-Level and Row-Level Security

### The PCI-DSS Challenge: Primary Account Numbers (PANs)

Card numbers (PANs) must never appear in plaintext for analysts. Lake Formation solves this:

```
Analyst Role (no PII access):
  SELECT card_number FROM transactions WHERE ...
  → Returns: card_number = "****-****-****-4242"  (masked by Lake Formation)

Compliance Role (full access):
  SELECT card_number FROM transactions WHERE ...
  → Returns: card_number = "4111111111114242"  (actual PAN)
```

### Lake Formation Permission Model

```
IAM Groups → Lake Formation Permissions → Glue Data Catalog → S3

Data Analyst:
  - Table: curated.transactions
  - Columns: ALL EXCEPT card_number, ssn, routing_number
  - Row filter: region = analyst's assigned region

Risk Analyst:
  - Table: curated.transactions, curated.fraud_signals
  - Columns: card_last_four (masked), amount, merchant, risk_score
  - Row filter: NONE (sees all regions)

Compliance Officer:
  - Table: ALL
  - Columns: ALL (unmasked)
  - Row filter: NONE

Data Engineer:
  - Full access to raw zone (for ETL debugging)
  - NO access to curated zone directly

External Auditor (read-only, time-limited):
  - Table: curated.audit_log only
  - Duration: 90-day IAM role (aws sts assume-role with condition)
```

---

## 6. Glue ETL Pipeline: PII Masking at Ingest

```python
# glue_jobs/transform_transactions.py
import sys
import hashlib
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from pyspark.sql import functions as F

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'source_path', 'dest_path'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# Read raw transactions
df = spark.read.json(args['source_path'])

# PII masking applied at ETL time — raw data stays in raw zone (restricted access)
df_masked = df.withColumn(
    "card_last_four",
    F.substring(F.col("card_number"), -4, 4)
).withColumn(
    "card_number_hash",
    F.sha2(F.col("card_number"), 256)
).withColumn(
    "card_number",
    F.lit("REDACTED")  # PAN never lands in curated zone in plaintext
).withColumn(
    "ssn",
    F.concat(F.lit("***-**-"), F.substring(F.col("ssn"), -4, 4))
)

# Partition and write to curated zone as Parquet
df_masked.write \
    .mode("append") \
    .partitionBy("year", "month", "day", "region") \
    .parquet(args['dest_path'])
```

---

## 7. Scaling Strategy

### Storage Scaling
- **S3:** Unlimited by design. No capacity planning needed.
- **Partitioning:** Day-level partitions prevent "small file problem" — Glue compaction job runs weekly to merge files < 128MB into optimal Parquet files.

### Query Scaling
- **Athena:** Concurrency quota = 20 queries per account (request increase to 50). Each query scales compute automatically.
- **Redshift Serverless:** Scales from 8 to 512 RPUs automatically based on query load. 0 cost when idle.

### Ingest Scaling
- **Glue:** 10 DPUs per job → 100 DPUs for end-of-month reconciliation batch
- **Kinesis Firehose:** Scales automatically to handle up to 1MB/s per shard (add shards for > 1GB/s)

---

## 8. Cost Optimization

### Monthly Cost Estimate

| Service | Usage | Monthly Cost |
|---------|-------|-------------|
| S3 (1TB/month, Standard) | 1TB raw + 200GB curated | ~$25 |
| S3 (Glacier for 7yr retention) | 10TB historical | ~$40 |
| Glue ETL (10 DPU × 2hr/day) | 600 DPU-hours/month | ~$132 |
| Athena | 2TB scanned/month | ~$10 |
| Redshift Serverless | 100 RPU-hours/month | ~$45 |
| Glue Data Catalog | 1M objects | ~$1 |
| Macie | 1TB scanned | ~$5 |
| KMS | 5 CMKs + API calls | ~$5 |
| **Total** | | **~$263/month** |

### Cost vs. Alternatives

| Option | Setup | Monthly Cost | Operational Overhead |
|--------|-------|-------------|---------------------|
| **This architecture** | 2 weeks | ~$263 | Low (serverless) |
| EMR + Hive | 4 weeks | ~$800 | High |
| Snowflake | 1 week | ~$1,200 | Low |
| Databricks | 3 weeks | ~$900 | Medium |

> **Tradeoff:** Snowflake is operationally simpler but 4x the cost. At ClearPay's current scale, AWS-native wins on cost. Reassess at > 10TB/day ingest volume.

### S3 Storage Tiering

```
Day 0-30:   S3 Standard     ($0.023/GB)  — active query access
Day 31-90:  S3 Standard-IA  ($0.0125/GB) — infrequent queries
Day 91-365: S3 Glacier IR   ($0.004/GB)  — compliance archive
Day 365+:   S3 Glacier DA   ($0.00099/GB) — 7-year retention at minimal cost
```

---

## 9. Failure Modes and Handling

| Failure | Impact | Mitigation |
|---------|--------|-----------|
| Glue job failure | Night's data not loaded | Glue job bookmarks track processed files; failed jobs restart from last checkpoint |
| Athena query timeout | Analyst query fails | Athena 30-min timeout; complex queries routed to Redshift; query result caching for repeated queries |
| S3 bucket unavailable | All queries fail | S3 99.999999999% durability; S3 Multi-Region Access Point for cross-region access |
| Data source schema change | ETL fails | Glue Schema Registry enforces contract; schema evolution with backward compatibility |
| Accidental data deletion | Data loss | S3 Versioning + MFA Delete; 90-day backup via AWS Backup |

---

## 10. CAP Theorem Position

The data lake is **CP (Consistent + Partition Tolerant)** by design:

- **Athena reads** are always consistent — they read directly from S3 which is strongly consistent (S3 Strong Consistency launched 2020)
- **ETL pipeline latency** = data is 1 day old (batch) or < 5 minutes old (streaming). This is **not eventual consistency** — it's **batch consistency**. Analysts understand they're querying yesterday's data.
- **Tradeoff accepted:** No real-time analytics (that's handled separately by the fraud engine's own database). The data lake optimizes for correctness and historical analysis, not real-time.

---

## 11. Architecture Diagram Layout

For draw.io or Excalidraw:
- **Left column:** 6 data source boxes (databases, APIs)
- **Center column (top to bottom):** Glue ETL → S3 zones (Raw, Curated, Aggregated) with arrows between them
- **Right column:** Athena + Redshift Serverless + QuickSight for query/BI
- **Bottom bar:** Lake Formation spanning the full width (as the security layer)
- **Side panel:** Macie, CloudTrail, KMS (compliance/security)
- Color: Orange = storage, Blue = compute/ETL, Purple = security, Yellow = BI

---

## Terraform Structure

```
terraform/
├── variables.tf        # Region, retention periods, compliance flags
├── s3_data_lake.tf     # Three S3 buckets (raw, curated, aggregated), lifecycle rules
├── glue.tf             # Glue jobs, crawlers, triggers, Data Catalog database
├── lake_formation.tf   # Data lake settings, permissions, LF-tags, column masking
├── athena.tf           # Athena workgroup, query result bucket, named queries
├── redshift.tf         # Redshift Serverless namespace, workgroup, IAM role
├── macie.tf            # Macie classification jobs, findings export to S3
├── kms.tf              # One CMK per data zone + Glue + Redshift
├── iam.tf              # Roles: data-analyst, risk-analyst, compliance, data-engineer
├── monitoring.tf       # CloudWatch alarms for Glue failures, Athena scan spikes
└── outputs.tf          # S3 bucket names, Glue database, Athena workgroup
```

---

## Interview Talking Points

**Q: Why not just use Snowflake?**  
Snowflake is an excellent product, but it's 4x more expensive than this AWS-native stack at ClearPay's current volume. More importantly, for PCI-DSS compliance, we need to demonstrate data never leaves our AWS environment and that we control the encryption keys. With Snowflake, you're delegating key management to a third party. Lake Formation gives us column-level masking without data leaving our VPC.

**Q: Why Athena instead of a traditional data warehouse?**  
The data access pattern is exploratory — analysts write one-off queries. A traditional data warehouse requires upfront schema design. Athena lets us query raw Parquet files with schema-on-read. We do use Redshift for the fixed, high-frequency dashboard queries where the 5-second response time requirement matters — Athena's 30-second cold start doesn't meet that SLA.

**Q: How do you handle the "small files problem" in S3?**  
Glue streaming jobs write many small files in real-time. We run a weekly Glue compaction job that reads all small files from a partition and rewrites them as fewer, larger Parquet files (128MB-512MB optimal size for Athena). This reduces Athena query cost by 60% (fewer S3 API calls) and improves scan speed.

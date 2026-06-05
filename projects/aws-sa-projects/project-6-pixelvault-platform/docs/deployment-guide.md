# PixelVault Deployment Guide

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Terraform | >= 1.6 | `brew install terraform` |
| AWS CLI | >= 2.15 | `brew install awscli` |
| jq | >= 1.6 | `brew install jq` |

Configure AWS credentials with an IAM role that has sufficient permissions:
```bash
aws configure sso
aws sts get-caller-identity
```

---

## Phase 1 — Bootstrap State Backend

Terraform stores state in S3 with DynamoDB locking. Create these manually **before** running any Terraform.

```bash
# Create state bucket
aws s3api create-bucket \
  --bucket pixelvault-terraform-state \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket pixelvault-terraform-state \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket pixelvault-terraform-state \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'

# Block all public access
aws s3api put-public-access-block \
  --bucket pixelvault-terraform-state \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Create DynamoDB lock table
aws dynamodb create-table \
  --table-name pixelvault-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

---

## Phase 2 — Package Lambda Source Code

Terraform references `.zip` files in `src/`. Build them before applying.

```bash
cd projects/project-6-pixelvault-platform/src

# Image processor (requires Pillow — install in package dir)
mkdir -p image_processor_pkg
pip install Pillow -t image_processor_pkg/
cp image_processor.py image_processor_pkg/
cd image_processor_pkg && zip -r ../image_processor.zip . && cd ..

# Fan-out worker
zip fan_out_worker.zip fan_out_worker.py

# Moderation worker
zip moderation_worker.zip moderation_worker.py

# Secret rotator
zip secret_rotator.zip secret_rotator.py
```

---

## Phase 3 — Create terraform.tfvars

```bash
cat > terraform/terraform.tfvars <<'EOF'
aws_region   = "us-east-1"
environment  = "production"
alarm_email  = "ops@yourdomain.com"

aurora_instance_class    = "db.r6g.2xlarge"
aurora_reader_count      = 2
redis_node_type          = "cache.r7g.xlarge"
redis_num_shards         = 3
redis_replicas_per_shard = 2

api_min_capacity     = 3
api_max_capacity     = 100
api_desired_capacity = 6
api_instance_type    = "c6i.xlarge"

cloudfront_price_class = "PriceClass_All"
EOF
```

---

## Phase 4 — Initialize and Plan

```bash
cd terraform/

terraform init

# Validate configuration
terraform validate

# Review all resources before applying (~95 resources)
terraform plan -var-file="terraform.tfvars" -out=plan.out
```

Expected resource count: **~95 resources** across VPC, compute, database, storage, and monitoring.

---

## Phase 5 — Apply in Stages

Apply in dependency order to minimize risk and make rollback easier.

**Stage 1: Networking (VPC, subnets, endpoints)**
```bash
terraform apply -target=aws_vpc.main \
  -target=aws_subnet.public \
  -target=aws_subnet.private_app \
  -target=aws_subnet.private_data \
  -target=aws_internet_gateway.main \
  -target=aws_nat_gateway.main \
  -target=aws_route_table.public \
  -target=aws_route_table.private_app \
  -target=aws_route_table.private_data \
  -var-file="terraform.tfvars"
```

**Stage 2: Security (KMS, security groups, WAF)**
```bash
terraform apply -target=aws_kms_key.aurora \
  -target=aws_kms_key.s3 \
  -target=aws_kms_key.secrets \
  -target=aws_kms_key.sqs \
  -target=aws_security_group.alb \
  -target=aws_security_group.api_servers \
  -target=aws_security_group.aurora \
  -target=aws_security_group.redis \
  -target=aws_wafv2_web_acl.main \
  -var-file="terraform.tfvars"
```

**Stage 3: Data layer (Aurora, Redis)**
```bash
terraform apply -target=aws_rds_cluster.main \
  -target=aws_rds_cluster_instance.writer \
  -target=aws_rds_cluster_instance.readers \
  -target=aws_elasticache_replication_group.main \
  -target=aws_dynamodb_table.feeds \
  -target=aws_dynamodb_table.notifications \
  -var-file="terraform.tfvars"
```

> Aurora provisioning takes 10–15 minutes. Redis cluster mode takes 5–10 minutes.

**Stage 4: Application layer and CDN**
```bash
# Apply everything remaining
terraform apply -var-file="terraform.tfvars"
```

---

## Phase 6 — Post-Deploy Verification

```bash
# Capture outputs
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain)
ALB_DNS=$(terraform output -raw alb_dns_name)
ORIGINAL_BUCKET=$(terraform output -raw images_original_bucket)
PROCESSED_BUCKET=$(terraform output -raw images_processed_bucket)

echo "CloudFront: $CLOUDFRONT_DOMAIN"
echo "ALB: $ALB_DNS"
```

### Health Checks

```bash
# 1. ALB health
curl -I "https://$ALB_DNS/health"
# Expected: HTTP 200

# 2. CloudFront cache
curl -I "https://$CLOUDFRONT_DOMAIN/health"
# Expected: HTTP 200, X-Cache: Hit from cloudfront (second request)

# 3. Generate pre-signed URL and test image upload
PRESIGNED_URL=$(aws s3 presign "s3://$ORIGINAL_BUCKET/test-upload.jpg" \
  --expires-in 300 --region us-east-1)

curl -X PUT "$PRESIGNED_URL" \
  --upload-file /path/to/test-image.jpg \
  -H "Content-Type: image/jpeg"
# Expected: HTTP 200 — triggers Lambda image processor

# 4. Verify processed image appears in processed bucket
sleep 30
aws s3 ls "s3://$PROCESSED_BUCKET/test-upload/" --recursive
# Expected: thumbnail_150.jpg, medium_600.jpg, full_1200.jpg

# 5. Verify CloudFront serves processed image
curl -I "https://$CLOUDFRONT_DOMAIN/images/test-upload/thumbnail_150.jpg"
# Expected: HTTP 200, Cache-Control: max-age=31536000

# 6. Aurora connectivity (from an EC2 instance in private subnet)
WRITER_ENDPOINT=$(terraform output -raw aurora_writer_endpoint)
mysql -h "$WRITER_ENDPOINT" -u pixelvault_admin -p"$(
  aws secretsmanager get-secret-value \
    --secret-id pixelvault-production/aurora/master-credentials \
    --query SecretString --output text | jq -r .password
)" pixelvault -e "SELECT @@aurora_version, @@read_only;"
# Expected: version returned, read_only = 0 (writer)

# 7. Redis connectivity
REDIS_ENDPOINT=$(terraform output -raw redis_configuration_endpoint)
REDIS_AUTH=$(aws secretsmanager get-secret-value \
  --secret-id pixelvault-production/redis/auth-token \
  --query SecretString --output text | jq -r .auth_token)

redis-cli -h "$REDIS_ENDPOINT" -p 6379 --tls \
  -a "$REDIS_AUTH" ping
# Expected: PONG
```

### CloudWatch Alarm Validation

```bash
# Confirm SNS subscription email was received and confirmed
aws sns list-subscriptions-by-topic \
  --topic-arn "$(terraform output -raw alarms_topic_arn)" \
  --query 'Subscriptions[].SubscriptionStatus'
# Expected: ["Confirmed"]

# View dashboard
DASHBOARD_URL=$(terraform output -raw cloudwatch_dashboard_url)
echo "Open in browser: $DASHBOARD_URL"
```

---

## Phase 7 — DNS Cutover

```bash
# Get CloudFront domain for CNAME record
CF_DOMAIN=$(terraform output -raw cloudfront_domain)
echo "Add CNAME: pixelvault.example.com → $CF_DOMAIN"

# Verify certificate validation (if not already done)
aws acm describe-certificate \
  --certificate-arn "$(terraform state show aws_acm_certificate.main | grep arn | awk '{print $3}')" \
  --query 'Certificate.Status'
# Must show "ISSUED" before CloudFront will serve HTTPS
```

---

## Rollback Procedure

If any stage fails, use targeted destroy to remove only the affected resources:

```bash
# Example: roll back compute layer only
terraform destroy \
  -target=aws_autoscaling_group.api_servers \
  -target=aws_lb.main \
  -var-file="terraform.tfvars"
```

**Never** run `terraform destroy` without `-target` in production.

---

## Ongoing Operations

### Rotate Redis Auth Token

```bash
# Terraform handles ROTATE strategy — re-apply triggers rotation
terraform apply -target=aws_elasticache_replication_group.main \
  -var-file="terraform.tfvars"
```

### Aurora Manual Snapshot

```bash
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier pixelvault-production-aurora-cluster \
  --db-cluster-snapshot-identifier "manual-$(date +%Y%m%d)"
```

### CloudFront Cache Invalidation

```bash
DIST_ID=$(terraform output -raw cloudfront_distribution_id)

aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
  --paths "/images/*"
```

### Scale ASG for Anticipated Traffic

```bash
# Pre-warm before a known viral event
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name pixelvault-production-api-asg \
  --desired-capacity 30
```

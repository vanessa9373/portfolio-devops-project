#!/bin/bash
##############################################################################
# Initialize Terraform Remote Backend (S3 + DynamoDB)
#
# Run this ONCE before using Terraform to set up state storage.
# Creates an S3 bucket for state and DynamoDB table for locking.
#
# Usage:
#   ./init-backend.sh [REGION]
#
# Example:
#   ./init-backend.sh us-east-1
##############################################################################

set -euo pipefail

REGION="${1:-us-east-1}"
BUCKET_NAME="sre-platform-terraform-state"
DYNAMODB_TABLE="terraform-locks"

echo "============================================"
echo "  Terraform Backend Initialization"
echo "============================================"
echo ""
echo "  Region:         $REGION"
echo "  S3 Bucket:      $BUCKET_NAME"
echo "  DynamoDB Table: $DYNAMODB_TABLE"
echo ""

# ── Create S3 Bucket ───────────────────────────────────────────────────
echo "[1/4] Creating S3 bucket for state storage..."
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "  Bucket already exists. Skipping."
else
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION"
    echo "  Bucket created."
fi

# ── Enable Versioning ──────────────────────────────────────────────────
echo "[2/4] Enabling bucket versioning..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled
echo "  Versioning enabled."

# ── Enable Encryption ──────────────────────────────────────────────────
echo "[3/4] Enabling bucket encryption..."
aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "aws:kms"
            },
            "BucketKeyEnabled": true
        }]
    }'
echo "  Encryption enabled (KMS)."

# ── Create DynamoDB Table ──────────────────────────────────────────────
echo "[4/4] Creating DynamoDB table for state locking..."
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" 2>/dev/null; then
    echo "  Table already exists. Skipping."
else
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$REGION"
    echo "  Table created."
fi

echo ""
echo "============================================"
echo "  Backend Ready!"
echo "============================================"
echo ""
echo "  Uncomment the backend \"s3\" block in your"
echo "  environment's main.tf, then run:"
echo ""
echo "    cd environments/dev"
echo "    terraform init"
echo ""
echo "============================================"

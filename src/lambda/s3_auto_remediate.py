"""
s3_auto_remediate.py — Lambda function triggered by AWS Config when an
S3 bucket is found without encryption or public access block.

Trigger: AWS Config Rule → EventBridge → Lambda

Auto-remediates:
  - Missing server-side encryption
  - Missing public access block configuration
"""

import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')


def handler(event, context):
    logger.info(f"Event received: {json.dumps(event)}")

    # Extract bucket name from Config event
    config_item = event.get('detail', {}).get('configurationItem', {})
    bucket_name = config_item.get('resourceId') or \
                  event.get('detail', {}).get('resourceId', '')

    if not bucket_name:
        logger.error("No bucket name found in event")
        return {'statusCode': 400, 'body': 'No bucket name in event'}

    results = []

    # ── Remediation 1: Enable encryption ────────────────────────────────────
    try:
        s3.get_bucket_encryption(Bucket=bucket_name)
        logger.info(f"{bucket_name}: encryption already enabled")
    except s3.exceptions.ClientError as e:
        if e.response['Error']['Code'] == 'ServerSideEncryptionConfigurationNotFoundError':
            s3.put_bucket_encryption(
                Bucket=bucket_name,
                ServerSideEncryptionConfiguration={
                    'Rules': [{
                        'ApplyServerSideEncryptionByDefault': {
                            'SSEAlgorithm': 'AES256'
                        },
                        'BucketKeyEnabled': True
                    }]
                }
            )
            logger.info(f"{bucket_name}: encryption ENABLED")
            results.append('encryption_enabled')

    # ── Remediation 2: Block public access ───────────────────────────────────
    try:
        block_config = s3.get_public_access_block(Bucket=bucket_name)
        cfg = block_config['PublicAccessBlockConfiguration']
        if not all([
            cfg.get('BlockPublicAcls'),
            cfg.get('IgnorePublicAcls'),
            cfg.get('BlockPublicPolicy'),
            cfg.get('RestrictPublicBuckets')
        ]):
            raise ValueError("Public access block incomplete")
        logger.info(f"{bucket_name}: public access block already configured")
    except Exception:
        s3.put_public_access_block(
            Bucket=bucket_name,
            PublicAccessBlockConfiguration={
                'BlockPublicAcls': True,
                'IgnorePublicAcls': True,
                'BlockPublicPolicy': True,
                'RestrictPublicBuckets': True
            }
        )
        logger.info(f"{bucket_name}: public access block ENABLED")
        results.append('public_access_blocked')

    return {
        'statusCode': 200,
        'body': json.dumps({
            'bucket': bucket_name,
            'remediations': results
        })
    }

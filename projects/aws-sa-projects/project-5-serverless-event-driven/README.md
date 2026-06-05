# Project 5 — Serverless Event-Driven Web Application

**Author:** Vanessa Awo · AWS Solutions Architect  
**Date:** September 2025  
**Difficulty:** Entry-Level  

---

## Project Overview

Designed and deployed a fully serverless web application using API Gateway, Lambda, DynamoDB, and SQS. The architecture eliminates idle compute costs, scales automatically, and handles asynchronous workloads through an event-driven design.

---

## Architecture Diagram

```
Client (Browser / Mobile)
         │
         ▼
  Amazon Cognito (Auth)
         │
         ▼
  API Gateway (REST API)
         │
    ┌────┴──────────────┐
    ▼                   ▼
Lambda (CRUD)     Lambda (Async)
    │                   │
    ▼                   ▼
DynamoDB            SQS Queue
                        │
                   Dead-Letter Queue
                        │
                   EventBridge
                   (Scheduled Rules)
         │
         ▼
    CloudWatch
    (Logs & Metrics)
```

---

## AWS Services Used

| Service | Purpose |
|---------|---------|
| Amazon API Gateway | REST API endpoint management |
| AWS Lambda | Serverless application logic |
| Amazon DynamoDB | NoSQL data storage |
| Amazon SQS | Asynchronous message queuing |
| Amazon EventBridge | Automated workflow triggers |
| Amazon Cognito | User authentication and authorization |
| AWS IAM | Least-privilege access policies |
| Amazon CloudWatch | Logs, metrics, and alarms |
| AWS WAF | API protection against OWASP threats |

---

## Step-by-Step Build Guide

### Step 1 — Create DynamoDB Table

```bash
aws dynamodb create-table \
  --table-name AppData \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --tags Key=Project,Value=serverless-app
```

### Step 2 — Create IAM Role for Lambda

```bash
aws iam create-role \
  --role-name lambda-execution-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam attach-role-policy \
  --role-name lambda-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Inline policy for DynamoDB and SQS
aws iam put-role-policy \
  --role-name lambda-execution-role \
  --policy-name lambda-app-policy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["dynamodb:GetItem","dynamodb:PutItem","dynamodb:UpdateItem","dynamodb:DeleteItem","dynamodb:Scan","dynamodb:Query"],
        "Resource": "arn:aws:dynamodb:*:*:table/AppData"
      },
      {
        "Effect": "Allow",
        "Action": ["sqs:SendMessage","sqs:ReceiveMessage","sqs:DeleteMessage","sqs:GetQueueAttributes"],
        "Resource": "*"
      }
    ]
  }'
```

### Step 3 — Create Lambda Functions

**CRUD Lambda (`app.py`):**
```python
import json
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('AppData')

def handler(event, context):
    method = event['httpMethod']
    
    if method == 'POST':
        body = json.loads(event['body'])
        item = {
            'id': str(uuid.uuid4()),
            'data': body,
            'createdAt': datetime.utcnow().isoformat()
        }
        table.put_item(Item=item)
        return {'statusCode': 201, 'body': json.dumps(item)}
    
    elif method == 'GET':
        result = table.scan()
        return {'statusCode': 200, 'body': json.dumps(result['Items'])}
    
    return {'statusCode': 400, 'body': json.dumps({'error': 'Unsupported method'})}
```

```bash
# Package and deploy
zip function.zip app.py

aws lambda create-function \
  --function-name app-crud \
  --runtime python3.11 \
  --handler app.handler \
  --role arn:aws:iam::<ACCOUNT_ID>:role/lambda-execution-role \
  --zip-file fileb://function.zip \
  --timeout 30 \
  --memory-size 256 \
  --environment Variables={TABLE_NAME=AppData}
```

### Step 4 — Create SQS Queue with Dead-Letter Queue

```bash
# Create dead-letter queue first
aws sqs create-queue --queue-name app-dlq

# Create main queue with DLQ
aws sqs create-queue \
  --queue-name app-queue \
  --attributes '{
    "VisibilityTimeout": "60",
    "MessageRetentionPeriod": "86400",
    "RedrivePolicy": "{\"deadLetterTargetArn\":\"arn:aws:sqs:<REGION>:<ACCOUNT_ID>:app-dlq\",\"maxReceiveCount\":\"3\"}"
  }'
```

**Async Lambda for queue processing (`processor.py`):**
```python
import json
import boto3

def handler(event, context):
    for record in event['Records']:
        body = json.loads(record['body'])
        print(f"Processing message: {body}")
        # Add your async processing logic here
    return {'statusCode': 200}
```

```bash
# Connect SQS to Lambda trigger
aws lambda create-event-source-mapping \
  --function-name app-processor \
  --event-source-arn arn:aws:sqs:<REGION>:<ACCOUNT_ID>:app-queue \
  --batch-size 10
```

### Step 5 — Set Up Amazon Cognito

```bash
# Create user pool
aws cognito-idp create-user-pool \
  --pool-name app-user-pool \
  --policies '{"PasswordPolicy":{"MinimumLength":8,"RequireUppercase":true,"RequireLowercase":true,"RequireNumbers":true}}' \
  --auto-verified-attributes email

# Create app client
aws cognito-idp create-user-pool-client \
  --user-pool-id <USER_POOL_ID> \
  --client-name app-client \
  --no-generate-secret
```

### Step 6 — Create API Gateway REST API

```bash
# Create REST API
aws apigateway create-rest-api \
  --name serverless-app-api \
  --description "Serverless App API"

# Create Cognito authorizer
aws apigateway create-authorizer \
  --rest-api-id <API_ID> \
  --name CognitoAuth \
  --type COGNITO_USER_POOLS \
  --provider-arns arn:aws:cognito-idp:<REGION>:<ACCOUNT_ID>:userpool/<USER_POOL_ID> \
  --identity-source method.request.header.Authorization

# Create resource and methods
aws apigateway create-resource \
  --rest-api-id <API_ID> \
  --parent-id <ROOT_RESOURCE_ID> \
  --path-part items

aws apigateway put-method \
  --rest-api-id <API_ID> \
  --resource-id <RESOURCE_ID> \
  --http-method POST \
  --authorization-type COGNITO_USER_POOLS \
  --authorizer-id <AUTHORIZER_ID>

# Deploy API
aws apigateway create-deployment \
  --rest-api-id <API_ID> \
  --stage-name prod
```

### Step 7 — Add AWS WAF

```bash
aws wafv2 create-web-acl \
  --name app-waf \
  --scope REGIONAL \
  --default-action Allow={} \
  --rules '[
    {
      "Name": "AWSManagedRulesCommonRuleSet",
      "Priority": 1,
      "OverrideAction": {"None": {}},
      "Statement": {
        "ManagedRuleGroupStatement": {
          "VendorName": "AWS",
          "Name": "AWSManagedRulesCommonRuleSet"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "CommonRuleSet"
      }
    }
  ]' \
  --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=app-waf
```

### Step 8 — Set Up EventBridge Scheduled Rule

```bash
aws events put-rule \
  --name daily-cleanup \
  --schedule-expression "cron(0 2 * * ? *)" \
  --state ENABLED

aws events put-targets \
  --rule daily-cleanup \
  --targets '[{"Id": "1", "Arn": "arn:aws:lambda:<REGION>:<ACCOUNT_ID>:function:app-processor"}]'
```

### Step 9 — CloudWatch Monitoring

```bash
# Lambda error alarm
aws cloudwatch put-metric-alarm \
  --alarm-name lambda-errors \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --dimensions Name=FunctionName,Value=app-crud \
  --statistic Sum \
  --period 60 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions <SNS_TOPIC_ARN>

# DLQ messages alarm
aws cloudwatch put-metric-alarm \
  --alarm-name dlq-messages \
  --metric-name ApproximateNumberOfMessagesVisible \
  --namespace AWS/SQS \
  --dimensions Name=QueueName,Value=app-dlq \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 1 \
  --alarm-actions <SNS_TOPIC_ARN>
```

---

## Skills Demonstrated

- Serverless architecture design
- Event-driven and asynchronous processing
- REST API development with API Gateway
- User authentication with Cognito
- Dead-letter queue implementation
- IAM least-privilege policies
- CloudWatch monitoring and alerting
- WAF security integration

---

## Resume Bullets

- Designed and deployed a serverless application using API Gateway, Lambda, DynamoDB, and SQS
- Configured Cognito authentication and IAM policies to secure APIs and application resources
- Implemented event-driven processing using EventBridge and dead-letter queues
- Monitored application logs and metrics using Amazon CloudWatch

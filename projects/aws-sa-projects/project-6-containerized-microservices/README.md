# Project 6 — Containerized Microservices Platform on AWS

**Author:** Vanessa Awo · AWS Solutions Architect  
**Date:** October 2025  
**Difficulty:** Entry-Level  

---

## Project Overview

Built a containerized microservices environment using Docker, Amazon ECS Fargate, and ECR with a fully automated CI/CD pipeline using CodePipeline and CodeBuild.

---

## Architecture Diagram

```
Developer → GitHub Push
                │
                ▼
         CodePipeline
         ┌──────┴───────┐
         ▼              ▼
      CodeBuild      CodeBuild
    (Build & Test)  (Docker Build)
         │              │
         └──────┬───────┘
                ▼
         Amazon ECR
         (Container Registry)
                │
                ▼
        ECS Fargate (Tasks)
         ┌──────┴───────┐
         ▼              ▼
   Service A        Service B
   (Container)      (Container)
         │              │
         └──────┬───────┘
                ▼
   Application Load Balancer
                │
              VPC
     (Public + Private Subnets)
                │
         CloudWatch Logs
```

---

## AWS Services Used

| Service | Purpose |
|---------|---------|
| Amazon ECS | Container orchestration |
| AWS Fargate | Serverless container compute |
| Amazon ECR | Container image registry |
| Application Load Balancer | Traffic distribution to containers |
| Amazon CloudWatch | Logs, metrics, container insights |
| AWS CodePipeline | CI/CD pipeline orchestration |
| AWS CodeBuild | Build, test, and Docker image creation |
| AWS IAM | Task roles and execution roles |
| Amazon VPC | Networking for ECS services |

---

## Step-by-Step Build Guide

### Step 1 — Create ECR Repository

```bash
# Create ECR repository
aws ecr create-repository \
  --repository-name my-app \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256

# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS \
  --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
```

### Step 2 — Build and Push Docker Image

**Sample `Dockerfile`:**
```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
EXPOSE 8080

CMD ["python", "app.py"]
```

**Sample `app.py`:**
```python
from flask import Flask, jsonify
app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})

@app.route('/')
def index():
    return jsonify({'message': 'Containerized Microservice Running'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

```bash
# Build and push
docker build -t my-app .
docker tag my-app:latest <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/my-app:latest
docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/my-app:latest
```

### Step 3 — Create VPC and Networking

```bash
# Create VPC
aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=ecs-vpc}]'

# Public subnets (for ALB)
aws ec2 create-subnet --vpc-id <VPC_ID> \
  --cidr-block 10.0.1.0/24 --availability-zone us-east-1a
aws ec2 create-subnet --vpc-id <VPC_ID> \
  --cidr-block 10.0.2.0/24 --availability-zone us-east-1b

# Private subnets (for ECS tasks)
aws ec2 create-subnet --vpc-id <VPC_ID> \
  --cidr-block 10.0.11.0/24 --availability-zone us-east-1a
aws ec2 create-subnet --vpc-id <VPC_ID> \
  --cidr-block 10.0.12.0/24 --availability-zone us-east-1b
```

### Step 4 — Create IAM Roles for ECS

```bash
# ECS Task Execution Role (for pulling images, CloudWatch logs)
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# ECS Task Role (for app-level AWS API calls)
aws iam create-role \
  --role-name ecsTaskRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'
```

### Step 5 — Create ECS Cluster

```bash
aws ecs create-cluster \
  --cluster-name my-app-cluster \
  --capacity-providers FARGATE FARGATE_SPOT \
  --default-capacity-provider-strategy \
    capacityProvider=FARGATE,weight=1 \
  --settings name=containerInsights,value=enabled
```

### Step 6 — Create ECS Task Definition

```bash
aws ecs register-task-definition \
  --family my-app-task \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu 256 \
  --memory 512 \
  --execution-role-arn arn:aws:iam::<ACCOUNT_ID>:role/ecsTaskExecutionRole \
  --task-role-arn arn:aws:iam::<ACCOUNT_ID>:role/ecsTaskRole \
  --container-definitions '[
    {
      "name": "my-app",
      "image": "<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/my-app:latest",
      "portMappings": [{"containerPort": 8080, "protocol": "tcp"}],
      "essential": true,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/my-app",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3
      }
    }
  ]'
```

### Step 7 — Create Application Load Balancer

```bash
# Create ALB
aws elbv2 create-load-balancer \
  --name my-app-alb \
  --subnets <PUBLIC_SUBNET_1A> <PUBLIC_SUBNET_1B> \
  --security-groups <ALB_SG_ID>

# Target group for ECS
aws elbv2 create-target-group \
  --name my-app-tg \
  --protocol HTTP --port 8080 \
  --vpc-id <VPC_ID> \
  --target-type ip \
  --health-check-path /health

# Listener
aws elbv2 create-listener \
  --load-balancer-arn <ALB_ARN> \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=<TG_ARN>
```

### Step 8 — Create ECS Service

```bash
aws ecs create-service \
  --cluster my-app-cluster \
  --service-name my-app-service \
  --task-definition my-app-task \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration '{
    "awsvpcConfiguration": {
      "subnets": ["<PRIVATE_SUBNET_1A>", "<PRIVATE_SUBNET_1B>"],
      "securityGroups": ["<ECS_SG_ID>"],
      "assignPublicIp": "DISABLED"
    }
  }' \
  --load-balancers '[{
    "targetGroupArn": "<TG_ARN>",
    "containerName": "my-app",
    "containerPort": 8080
  }]' \
  --deployment-configuration '{
    "maximumPercent": 200,
    "minimumHealthyPercent": 100
  }'
```

### Step 9 — Set Up CodePipeline CI/CD

**`buildspec.yml`** (CodeBuild):
```yaml
version: 0.2
phases:
  pre_build:
    commands:
      - aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REPO
  build:
    commands:
      - docker build -t $ECR_REPO:$CODEBUILD_RESOLVED_SOURCE_VERSION .
      - docker tag $ECR_REPO:$CODEBUILD_RESOLVED_SOURCE_VERSION $ECR_REPO:latest
  post_build:
    commands:
      - docker push $ECR_REPO:$CODEBUILD_RESOLVED_SOURCE_VERSION
      - docker push $ECR_REPO:latest
      - printf '[{"name":"my-app","imageUri":"%s"}]' $ECR_REPO:$CODEBUILD_RESOLVED_SOURCE_VERSION > imagedefinitions.json
artifacts:
  files:
    - imagedefinitions.json
```

```bash
# Create CodePipeline
aws codepipeline create-pipeline \
  --pipeline '{
    "name": "my-app-pipeline",
    "roleArn": "arn:aws:iam::<ACCOUNT_ID>:role/CodePipelineRole",
    "stages": [
      {
        "name": "Source",
        "actions": [{
          "name": "Source",
          "actionTypeId": {"category": "Source","owner": "ThirdParty","provider": "GitHub","version": "1"},
          "configuration": {"Owner": "vanessa9373","Repo": "my-app","Branch": "main","OAuthToken": "<GITHUB_TOKEN>"},
          "outputArtifacts": [{"name": "SourceOutput"}]
        }]
      },
      {
        "name": "Build",
        "actions": [{
          "name": "Build",
          "actionTypeId": {"category": "Build","owner": "AWS","provider": "CodeBuild","version": "1"},
          "inputArtifacts": [{"name": "SourceOutput"}],
          "outputArtifacts": [{"name": "BuildOutput"}],
          "configuration": {"ProjectName": "my-app-build"}
        }]
      },
      {
        "name": "Deploy",
        "actions": [{
          "name": "Deploy",
          "actionTypeId": {"category": "Deploy","owner": "AWS","provider": "ECS","version": "1"},
          "inputArtifacts": [{"name": "BuildOutput"}],
          "configuration": {"ClusterName": "my-app-cluster","ServiceName": "my-app-service","FileName": "imagedefinitions.json"}
        }]
      }
    ],
    "artifactStore": {"type": "S3","location": "my-app-artifacts-bucket"}
  }'
```

### Step 10 — CloudWatch Container Insights

```bash
# Create log group
aws logs create-log-group --log-group-name /ecs/my-app

# Container memory alarm
aws cloudwatch put-metric-alarm \
  --alarm-name ecs-high-memory \
  --metric-name MemoryUtilization \
  --namespace AWS/ECS \
  --dimensions Name=ClusterName,Value=my-app-cluster Name=ServiceName,Value=my-app-service \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions <SNS_TOPIC_ARN>
```

---

## Skills Demonstrated

- Docker containerization
- Amazon ECS Fargate (serverless containers)
- Container image management with ECR
- CI/CD pipeline automation (CodePipeline + CodeBuild)
- Load balancing for containerized services
- CloudWatch Container Insights and logging
- IAM task roles and execution roles
- VPC networking for ECS

---

## Resume Bullets

- Built and deployed containerized applications using Docker, Amazon ECS, and AWS Fargate
- Configured CI/CD pipelines using CodePipeline and CodeBuild for automated deployments
- Implemented load balancing and monitoring using Application Load Balancer and CloudWatch
- Managed container images using Amazon ECR and configured secure IAM access

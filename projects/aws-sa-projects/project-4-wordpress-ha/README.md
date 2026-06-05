# Project 4 — Highly Available WordPress Website on AWS

**Author:** Vanessa Awo · AWS Solutions Architect  
**Date:** July 2025  
**Difficulty:** Entry-Level  

---

## Project Overview

Built and deployed a highly available WordPress application on AWS using EC2, RDS Multi-AZ, Auto Scaling, and an Application Load Balancer — designed for zero single points of failure across two Availability Zones.

---

## Architecture Diagram

```
Internet
    │
    ▼
Route 53 (DNS)
    │
    ▼
CloudFront (CDN)
    │
    ▼
Application Load Balancer
    │
    ├──────────────────────┐
    ▼                      ▼
EC2 (AZ-1)           EC2 (AZ-2)
WordPress            WordPress
    │                      │
    └──────────┬───────────┘
               ▼
        RDS Multi-AZ
        (Primary + Standby)
               │
         S3 (Static Assets)
         AWS Backup
```

---

## AWS Services Used

| Service | Purpose |
|---------|---------|
| Amazon EC2 | WordPress web servers |
| Application Load Balancer | Traffic distribution across AZs |
| Auto Scaling Groups | Automatic scaling based on CPU |
| Amazon RDS MySQL Multi-AZ | Highly available managed database |
| Amazon S3 | Static asset storage |
| Amazon CloudFront | Global CDN for fast content delivery |
| Amazon Route 53 | DNS management |
| AWS IAM | Least-privilege roles and policies |
| Amazon CloudWatch | Monitoring, dashboards, and alarms |
| AWS Backup | Automated backup management |

---

## Step-by-Step Build Guide

### Step 1 — Create VPC and Networking

```bash
# Create VPC
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications \
  'ResourceType=vpc,Tags=[{Key=Name,Value=wordpress-vpc}]'

# Create public subnets in two AZs
aws ec2 create-subnet --vpc-id <VPC_ID> \
  --cidr-block 10.0.1.0/24 --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-subnet-1a}]'

aws ec2 create-subnet --vpc-id <VPC_ID> \
  --cidr-block 10.0.2.0/24 --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-subnet-1b}]'

# Create private subnets for RDS
aws ec2 create-subnet --vpc-id <VPC_ID> \
  --cidr-block 10.0.11.0/24 --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-subnet-1a}]'

aws ec2 create-subnet --vpc-id <VPC_ID> \
  --cidr-block 10.0.12.0/24 --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-subnet-1b}]'

# Create and attach Internet Gateway
aws ec2 create-internet-gateway
aws ec2 attach-internet-gateway --vpc-id <VPC_ID> --internet-gateway-id <IGW_ID>
```

### Step 2 — Create Security Groups

```bash
# ALB security group — allow HTTP/HTTPS from internet
aws ec2 create-security-group --group-name alb-sg \
  --description "ALB Security Group" --vpc-id <VPC_ID>
aws ec2 authorize-security-group-ingress --group-id <ALB_SG_ID> \
  --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id <ALB_SG_ID> \
  --protocol tcp --port 443 --cidr 0.0.0.0/0

# EC2 security group — allow HTTP from ALB only
aws ec2 create-security-group --group-name ec2-sg \
  --description "EC2 Security Group" --vpc-id <VPC_ID>
aws ec2 authorize-security-group-ingress --group-id <EC2_SG_ID> \
  --protocol tcp --port 80 --source-group <ALB_SG_ID>

# RDS security group — allow MySQL from EC2 only
aws ec2 create-security-group --group-name rds-sg \
  --description "RDS Security Group" --vpc-id <VPC_ID>
aws ec2 authorize-security-group-ingress --group-id <RDS_SG_ID> \
  --protocol tcp --port 3306 --source-group <EC2_SG_ID>
```

### Step 3 — Create RDS MySQL Multi-AZ

```bash
# Create DB subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name wordpress-subnet-group \
  --db-subnet-group-description "WordPress DB Subnet Group" \
  --subnet-ids <PRIVATE_SUBNET_1A_ID> <PRIVATE_SUBNET_1B_ID>

# Create RDS Multi-AZ instance
aws rds create-db-instance \
  --db-instance-identifier wordpress-db \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --engine-version 8.0 \
  --master-username admin \
  --master-user-password <STRONG_PASSWORD> \
  --allocated-storage 20 \
  --multi-az \
  --db-subnet-group-name wordpress-subnet-group \
  --vpc-security-group-ids <RDS_SG_ID> \
  --backup-retention-period 7 \
  --storage-encrypted \
  --db-name wordpress
```

### Step 4 — Create S3 Bucket for Static Assets

```bash
aws s3 mb s3://wordpress-static-assets-<ACCOUNT_ID>
aws s3api put-bucket-versioning \
  --bucket wordpress-static-assets-<ACCOUNT_ID> \
  --versioning-configuration Status=Enabled
```

### Step 5 — Create IAM Role for EC2

```bash
# Create IAM role
aws iam create-role \
  --role-name wordpress-ec2-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach S3 and SSM policies
aws iam attach-role-policy \
  --role-name wordpress-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-role-policy \
  --role-name wordpress-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile --instance-profile-name wordpress-ec2-profile
aws iam add-role-to-instance-profile \
  --instance-profile-name wordpress-ec2-profile \
  --role-name wordpress-ec2-role
```

### Step 6 — Create Launch Template

```bash
aws ec2 create-launch-template \
  --launch-template-name wordpress-lt \
  --launch-template-data '{
    "ImageId": "ami-0c02fb55956c7d316",
    "InstanceType": "t3.micro",
    "SecurityGroupIds": ["<EC2_SG_ID>"],
    "IamInstanceProfile": {"Name": "wordpress-ec2-profile"},
    "UserData": "<BASE64_ENCODED_USERDATA>"
  }'
```

**User Data Script (WordPress install):**
```bash
#!/bin/bash
yum update -y
yum install -y httpd php php-mysqlnd
systemctl start httpd && systemctl enable httpd
cd /var/www/html
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* .
rm -rf wordpress latest.tar.gz
chown -R apache:apache /var/www/html
```

### Step 7 — Create Application Load Balancer

```bash
# Create ALB
aws elbv2 create-load-balancer \
  --name wordpress-alb \
  --subnets <PUBLIC_SUBNET_1A> <PUBLIC_SUBNET_1B> \
  --security-groups <ALB_SG_ID> \
  --scheme internet-facing

# Create target group
aws elbv2 create-target-group \
  --name wordpress-tg \
  --protocol HTTP --port 80 \
  --vpc-id <VPC_ID> \
  --health-check-path /wp-admin/install.php

# Create listener
aws elbv2 create-listener \
  --load-balancer-arn <ALB_ARN> \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=<TG_ARN>
```

### Step 8 — Create Auto Scaling Group

```bash
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name wordpress-asg \
  --launch-template LaunchTemplateName=wordpress-lt,Version='$Latest' \
  --min-size 2 --max-size 6 --desired-capacity 2 \
  --vpc-zone-identifier "<PUBLIC_SUBNET_1A>,<PUBLIC_SUBNET_1B>" \
  --target-group-arns <TG_ARN> \
  --health-check-type ELB \
  --health-check-grace-period 300

# CPU-based scaling policy
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name wordpress-asg \
  --policy-name cpu-scale-out \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "TargetValue": 70.0
  }'
```

### Step 9 — Set Up CloudFront

```bash
aws cloudfront create-distribution \
  --origin-domain-name <ALB_DNS_NAME> \
  --default-root-object index.php
```

### Step 10 — CloudWatch Monitoring

```bash
# CPU alarm
aws cloudwatch put-metric-alarm \
  --alarm-name wordpress-high-cpu \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions <SNS_TOPIC_ARN>

# ALB 5XX errors alarm
aws cloudwatch put-metric-alarm \
  --alarm-name wordpress-5xx-errors \
  --metric-name HTTPCode_ELB_5XX_Count \
  --namespace AWS/ApplicationELB \
  --statistic Sum \
  --period 60 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions <SNS_TOPIC_ARN>
```

### Step 11 — Configure AWS Backup

```bash
aws backup create-backup-plan \
  --backup-plan '{
    "BackupPlanName": "wordpress-backup-plan",
    "Rules": [{
      "RuleName": "daily-backup",
      "TargetBackupVaultName": "Default",
      "ScheduleExpression": "cron(0 5 ? * * *)",
      "DeleteAfterDays": 30
    }]
  }'
```

---

## Skills Demonstrated

- High availability architecture (Multi-AZ)
- AWS networking — VPC, subnets, security groups, IGW
- Load balancing and auto scaling
- Managed database with automated failover
- CloudFront CDN integration
- CloudWatch monitoring and alerting
- Backup and disaster recovery
- IAM least-privilege design

---

## Resume Bullets

- Built and deployed a highly available WordPress application using EC2, Auto Scaling Groups, Application Load Balancer, and RDS Multi-AZ
- Configured CloudFront and S3 to improve website performance and static content delivery
- Implemented CloudWatch dashboards and alarms to monitor system health and uptime
- Applied IAM security best practices and automated backups using AWS Backup

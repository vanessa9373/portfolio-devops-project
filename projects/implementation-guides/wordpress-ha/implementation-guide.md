# Highly Available WordPress Infrastructure on AWS
**Project:** Highly Available WordPress Infrastructure  
**Cloud:** Amazon Web Services  
**Completed:** February 2026  
**Services:** EC2, ALB, Auto Scaling, RDS Multi-AZ, EFS, S3, CloudFront, Route 53, ACM, CloudWatch, AWS Backup, IAM

---

## Overview

This guide documents the professional implementation of a Highly Available WordPress environment on AWS. The architecture prioritizes reliability, security, and automatic scaling as traffic grows, following AWS Well-Architected Framework principles.

---

## Phase 1: Networking & Security Foundation

Before deploying any servers, establish a secure and isolated network environment.

### Steps

1. **Create a VPC**  
   Define a Virtual Private Cloud with a non-overlapping CIDR block (e.g., `10.0.0.0/16`).

2. **Subnet Strategy**  
   Create subnets across at least two Availability Zones (AZs):
   - **Public Subnets** — for the Application Load Balancer
   - **Private Subnets** — for EC2 instances and the RDS database

3. **Internet Gateway & NAT Gateways**  
   - Attach an Internet Gateway to the VPC for public-facing traffic.
   - Deploy NAT Gateways in each public subnet so private instances can download updates without direct internet exposure.

4. **Security Groups**

   | Security Group | Inbound Rule | Source |
   |---|---|---|
   | ALB SG | HTTP (80), HTTPS (443) | `0.0.0.0/0` |
   | Web SG | HTTP (80) | ALB Security Group |
   | DB SG | MySQL (3306) | Web Security Group |

---

## Phase 2: Storage & Database Setup

1. **Amazon EFS (Elastic File System)**  
   Create a shared file system so all WordPress EC2 instances share the same `wp-content` folder (plugins, themes, media uploads).
   - Create Mount Targets in each private subnet where EC2 instances will run.
   - This is critical for HA — without shared storage, uploads on one instance would be invisible to others.

2. **Amazon RDS (Multi-AZ)**  
   - Launch a MySQL or Aurora MySQL instance.
   - Enable **Multi-AZ deployment** so AWS automatically maintains a synchronous standby replica in a separate AZ.
   - On failure, AWS promotes the standby automatically with no manual intervention.

3. **Amazon S3**  
   Create a bucket to offload static media and store database backups, reducing load on web servers.

---

## Phase 3: Compute & Auto Scaling

1. **Launch Template**  
   Define your EC2 configuration:
   - Instance type: `t3.medium` (adjust based on load)
   - AMI: Amazon Linux 2023
   - IAM Instance Profile with permissions for S3 and CloudWatch
   - **User Data Script** to auto-install Apache/Nginx + PHP and mount the EFS volume on every boot

   Example User Data (Amazon Linux 2023):
   ```bash
   #!/bin/bash
   yum update -y
   yum install -y httpd php php-mysqlnd amazon-efs-utils
   mount -t efs fs-XXXXXXXX:/ /var/www/html/wp-content
   echo "fs-XXXXXXXX:/ /var/www/html/wp-content efs defaults,_netdev 0 0" >> /etc/fstab
   systemctl start httpd
   systemctl enable httpd
   ```

2. **Auto Scaling Group (ASG)**  
   - Link to the Launch Template.
   - Set **minimum 2 instances** (one per AZ) and a maximum based on budget.
   - Configure scaling policies based on CPU utilization (e.g., scale out at 70%).

3. **Application Load Balancer (ALB)**  
   - Create an ALB in the public subnets.
   - Create a **Target Group** pointing to the ASG.
   - Configure health checks so the ALB routes traffic only to healthy instances.

---

## Phase 4: Optimization & Content Delivery

1. **Amazon CloudFront**  
   - Create a distribution with the ALB as the origin.
   - CloudFront caches content at edge locations globally, reducing latency for end users worldwide.
   - Configure cache behaviors to bypass CloudFront for admin paths (`/wp-admin/*`).

2. **Route 53**  
   - Map your domain name to the CloudFront distribution using an **Alias record** (not a CNAME) for root domain support.

3. **SSL/TLS with ACM**  
   - Use **AWS Certificate Manager (ACM)** to provision a free SSL/TLS certificate.
   - Attach it to the CloudFront distribution (or ALB) to enforce HTTPS.

---

## Phase 5: Monitoring & Maintenance

1. **CloudWatch Dashboards**  
   Set up dashboards and alarms to monitor:
   - EC2 CPU utilization
   - RDS connections and storage
   - ALB request count and 5xx error rates
   - ASG instance counts

2. **AWS Backup**  
   Create an automated backup plan for:
   - Daily RDS snapshots (retained 7–30 days)
   - EFS backups

3. **IAM Instance Profile (Least Privilege)**  
   Ensure EC2 instances only have the permissions they need:
   - `s3:GetObject`, `s3:PutObject` on the specific S3 bucket
   - `cloudwatch:PutMetricData`
   - `logs:CreateLogStream`, `logs:PutLogEvents`

---

## Architecture Diagram (Logical)

```
Internet
    │
[Route 53] ──► [CloudFront] ──► [ACM Certificate]
                    │
              [ALB — Public Subnets]
              /          \
    [EC2 AZ-1]          [EC2 AZ-2]     ← Auto Scaling Group
    (Private)           (Private)
        │                   │
        └───── [EFS] ───────┘           ← Shared wp-content
                    │
              [RDS Multi-AZ]            ← Primary + Standby
              /
          [S3 Bucket]                   ← Static assets & backups
```

---

## Key Architecture Decisions

| Decision | Choice | Reason |
|---|---|---|
| Storage for wp-content | EFS | Shared across all instances — required for HA |
| Database | RDS Multi-AZ | Automatic failover, no data loss |
| Load balancer | ALB | Layer 7, path-based routing, health checks |
| CDN | CloudFront | Global edge caching, HTTPS termination |
| Scaling | ASG with CPU target | Handles traffic spikes automatically |

---

## References

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Scalable WordPress Architecture Guide](https://numericaideas.com/blog/aws-scale-wordpress/)
- [Amazon EFS with WordPress](https://aws.amazon.com/getting-started/hands-on/scale-wordpress-site/)

# SRE Project 4: Infrastructure as Code — Summary

## The Story

After building observability (Project 1), CI/CD pipelines (Project 2), and incident response frameworks (Project 3), the next question was: **"How do we manage infrastructure at scale without manual work?"**

Clicking through AWS consoles doesn't scale. Infrastructure needs to be versioned, reviewable, repeatable, and testable — just like application code. This project implements that philosophy using Terraform for provisioning and Ansible for configuration management.

---

## What I Built

### Terraform Infrastructure (4 Reusable Modules)

**VPC Module** — Production-ready networking with public and private subnets across multiple Availability Zones, Internet Gateway, NAT Gateway for private subnet internet access, and VPC Flow Logs for security monitoring. Each environment gets its own CIDR range (10.0/10.1/10.2) to support VPC peering if needed.

**Compute Module** — EC2 instances behind an Application Load Balancer with Auto Scaling. The launch template uses IMDSv2 (security best practice), installs Docker and monitoring agents via user data, and connects to SSM Session Manager for keyless SSH access. Auto-scaling is configured with target tracking on CPU utilization.

**Kubernetes Module** — EKS cluster with managed node groups, IRSA (IAM Roles for Service Accounts), and all essential add-ons (CoreDNS, kube-proxy, VPC-CNI). Production config uses private API endpoint and all cluster log types enabled.

**Monitoring Module** — CloudWatch dashboards showing CPU, instance count, request volume, response time, and error rates. SNS topic for alert delivery. Alarms for high CPU, 5xx errors, and unhealthy targets — each with different thresholds per environment.

### Three Environment Configurations

I created three environments that demonstrate the promotion workflow:

**Dev** — Cost-optimized: 2 AZs, t3.micro instances, 1 instance minimum, no NAT Gateway, no EKS, relaxed alert thresholds.

**Staging** — Production-like: 2 AZs, t3.small instances, 2 instances, NAT Gateway, EKS cluster, moderate alert thresholds. Mirrors prod architecture for realistic pre-production testing.

**Prod** — Full high-availability: 3 AZs, t3.large instances, 3 instance minimum (one per AZ), private EKS API, VPC Flow Logs, tight alert thresholds (70% CPU, 5 error tolerance).

### Ansible Configuration Management (4 Roles)

**Common Role** — Base setup for every server: system updates, essential packages (vim, curl, jq, htop), UTC timezone, NTP via chronyd, sysctl tuning (65K connections, file descriptors), and application directory structure.

**Docker Role** — Full Docker CE installation with a production daemon.json configuration: overlay2 storage driver, JSON file logging with size limits, Docker metrics endpoint enabled for Prometheus scraping, and log rotation via logrotate.

**Monitoring Role** — Installs Prometheus Node Exporter (for infrastructure metrics that Prometheus scrapes) and CloudWatch Agent (for AWS-native monitoring). Both configured as systemd services with auto-restart.

**Hardening Role** — Security hardening based on CIS Benchmarks: SSH hardened (no root login, no password auth, protocol 2 only), firewalld configured with least-privilege port rules, dangerous kernel parameters disabled (ICMP redirects, source routing), auditd configured to monitor login events, sudo changes, SSH config modifications, and Docker usage. File permissions locked down on sensitive system files.

### Operational Playbooks

**site.yml** — Full infrastructure provisioning. Applies all roles in the correct order across all hosts, with a verification phase that confirms Node Exporter is running on every server.

**deploy-app.yml** — Zero-downtime rolling deployment. Processes one host at a time (`serial: 1`): drains traffic, waits for in-flight requests, pulls new image, starts container with health checks, waits for healthy status, then re-enables traffic.

**security-audit.yml** — Generates a comprehensive compliance report: SSH configuration, firewall status, users with empty passwords, unauthorized UID 0 accounts, world-writable files, unowned files, listening ports, and pending security updates.

---

## The Problem I Solved

**Before IaC:** Infrastructure is created manually via console clicks. Nobody knows the exact state. Changes are undocumented. Recreating an environment takes days of tribal knowledge. Server configurations drift over time.

**After IaC:**
- Infrastructure is **version-controlled** — every change is a PR that can be reviewed
- Environments are **reproducible** — `terraform apply` creates identical infrastructure every time
- Server configuration is **consistent** — Ansible ensures every server has the same setup
- Deployments are **automated** — rolling updates with health checks, no manual steps
- Security is **auditable** — run the audit playbook to verify compliance anytime
- Promotion is **safe** — changes flow through dev → staging → prod with `terraform plan` visibility

---

## Key Technical Decisions

### Why Terraform Modules?
Modules eliminate duplication. The VPC module is written once but used in dev, staging, and prod with different parameters. When we need to update the VPC (e.g., add a new route table rule), we change it in one place and all environments get the update.

### Why Separate Environments as Directories (Not Workspaces)?
Directories give each environment its own state file, variables, and backend configuration. This is safer than workspaces because you can't accidentally `terraform destroy` prod when you meant dev. The Google SRE Book recommends environment isolation as a safety practice.

### Why Ansible Roles (Not Just Playbooks)?
Roles are reusable and composable. The monitoring role works whether applied to webservers, databases, or monitoring hosts. We can mix and match roles per host group without duplicating tasks. This follows the DRY principle for configuration management.

### Why Both Terraform AND Ansible?
They solve different problems:
- **Terraform** excels at provisioning (creating infrastructure resources)
- **Ansible** excels at configuration (installing software, tuning settings)

Terraform could install Docker via user_data, but Ansible does it better: it's idempotent, testable, and can update existing servers (not just new ones).

### Why IMDSv2 and SSM Instead of SSH Keys?
IMDSv2 prevents SSRF attacks from stealing instance credentials. SSM Session Manager provides shell access without opening port 22 or managing SSH keys — reducing attack surface and key rotation overhead.

---

## What I Learned

1. **IaC is a team multiplier** — One person writes the module, everyone uses it with confidence
2. **`terraform plan` is your safety net** — Always review the plan before applying, especially in prod
3. **State management is critical** — Remote state with locking prevents concurrent modification disasters
4. **Idempotency matters** — Both Terraform and Ansible must be safe to run repeatedly
5. **Environment parity reduces surprises** — Staging should mirror prod as closely as budget allows
6. **Security should be default, not optional** — The hardening role runs on every server, not just prod
7. **Rolling deployments protect users** — One host at a time means a bad deploy affects minimal traffic

---

## Technologies Used

| Technology | Purpose |
|-----------|---------|
| Terraform | Infrastructure provisioning (AWS resources) |
| Ansible | Server configuration management |
| AWS (VPC, EC2, EKS, ALB, ASG, CloudWatch, SNS) | Cloud infrastructure |
| Docker | Application container runtime |
| Prometheus Node Exporter | Infrastructure metrics |
| CloudWatch Agent | AWS-native monitoring |
| S3 + DynamoDB | Terraform state backend |

---

## How to Talk About This in Interviews

> "I built a complete Infrastructure as Code framework using Terraform and Ansible. Terraform provisions the cloud infrastructure — VPCs with public/private subnets, auto-scaling EC2 instances behind an ALB, EKS clusters, and CloudWatch monitoring. I structured it into reusable modules that are shared across three environments: dev, staging, and production, each with appropriate sizing and security settings.

> Ansible handles server configuration — four roles that install Docker, set up monitoring agents, apply CIS Benchmark hardening, and maintain consistent base configurations. I also created a zero-downtime deployment playbook that does rolling updates with health check verification.

> The key insight is that Terraform and Ansible are complementary tools. Terraform is declarative — you describe what you want and it figures out how to get there. Ansible is procedural — you describe the steps to configure a server. Using both gives you reproducible infrastructure from bare metal to running application.

> A critical SRE practice I implemented is environment promotion: changes are tested in dev, validated in staging (which mirrors prod architecture), then applied to production. Every change is a code review, and `terraform plan` shows exactly what will change before it's applied."

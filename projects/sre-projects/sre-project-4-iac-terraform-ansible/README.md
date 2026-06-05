# Project 4: Infrastructure as Code with Terraform & Ansible

## Overview

This project implements a production-ready Infrastructure as Code (IaC) framework using **Terraform** for provisioning and **Ansible** for configuration management. It covers the full lifecycle — from creating cloud infrastructure (VPC, EC2, EKS, ALB, monitoring) to configuring servers (Docker, security hardening, monitoring agents) and deploying applications with zero-downtime rolling updates.

**Skills practiced:** Terraform modules, state management, multi-environment promotion (dev → staging → prod), Ansible roles/playbooks, server hardening, rolling deployments, security auditing.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Infrastructure as Code                     │
│                                                               │
│  ┌─────────────────────┐    ┌──────────────────────────┐     │
│  │     TERRAFORM        │    │       ANSIBLE             │     │
│  │  (Provisioning)      │    │  (Configuration)          │     │
│  │                      │    │                           │     │
│  │  Modules:            │    │  Roles:                   │     │
│  │  ├── vpc             │    │  ├── common (base setup)  │     │
│  │  ├── compute (EC2)   │    │  ├── docker (install)     │     │
│  │  ├── kubernetes (EKS)│    │  ├── monitoring (agents)  │     │
│  │  └── monitoring (CW) │    │  └── hardening (security) │     │
│  │                      │    │                           │     │
│  │  Environments:       │    │  Playbooks:               │     │
│  │  ├── dev    (small)  │    │  ├── site.yml (full)      │     │
│  │  ├── staging (mid)   │    │  ├── deploy-app.yml       │     │
│  │  └── prod   (HA)     │    │  └── security-audit.yml   │     │
│  └─────────────────────┘    └──────────────────────────┘     │
│                                                               │
│  Workflow: Terraform creates → Ansible configures → Deploy    │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- **Terraform** >= 1.5.0 (`brew install terraform`)
- **Ansible** >= 2.15 (`pip install ansible`)
- **AWS CLI** configured with credentials (`aws configure`)
- **kubectl** for EKS cluster management

---

## Project Structure

```
project4/
├── README.md
├── SRE-Project4-Summary.md
├── terraform/
│   ├── modules/
│   │   ├── vpc/              # VPC, subnets, IGW, NAT, flow logs
│   │   ├── compute/          # EC2, ASG, ALB, security groups
│   │   ├── kubernetes/       # EKS cluster, node groups, IRSA
│   │   └── monitoring/       # CloudWatch dashboards, alarms, SNS
│   └── environments/
│       ├── dev/              # Small, cost-optimized (t3.micro, 1 instance)
│       ├── staging/          # Production-like (t3.small, 2 instances, EKS)
│       └── prod/             # Full HA (t3.large, 3 AZs, 3+ instances, EKS)
├── ansible/
│   ├── ansible.cfg           # Ansible configuration
│   ├── inventory/
│   │   └── hosts.yml         # Static inventory (replace with aws_ec2 plugin)
│   ├── roles/
│   │   ├── common/           # Base packages, NTP, sysctl, file limits
│   │   ├── docker/           # Docker CE, daemon config, log rotation
│   │   ├── monitoring/       # Node Exporter, CloudWatch Agent
│   │   └── hardening/        # SSH, firewall, kernel security, audit
│   └── playbooks/
│       ├── site.yml          # Full provisioning (all roles)
│       ├── deploy-app.yml    # Zero-downtime rolling deployment
│       └── security-audit.yml # Compliance check report
└── scripts/
    ├── init-backend.sh       # Create S3 + DynamoDB for TF state
    └── validate-all.sh       # Validate all TF + Ansible configs
```

---

## Terraform Deep Dive

### Module Design

Each module follows the standard pattern:
- `main.tf` — Resource definitions
- `variables.tf` — Input parameters with defaults
- `outputs.tf` — Values exposed to other modules

### Environment Differences

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| AZs | 2 | 2 | 3 |
| NAT Gateway | No (cost saving) | Yes | Yes |
| Instance Type | t3.micro | t3.small | t3.large |
| Min Instances | 1 | 1 | 3 |
| Max Instances | 2 | 3 | 10 |
| EKS | No | Yes | Yes (private API) |
| Flow Logs | No | No | Yes |
| CPU Alarm | 80% | 75% | 70% |
| Error Threshold | 50 | 20 | 5 |

### State Management

```bash
# Initialize backend (run once)
./scripts/init-backend.sh us-east-1

# Deploy dev environment
cd terraform/environments/dev
terraform init
terraform plan
terraform apply

# Promote to staging
cd ../staging
terraform init
terraform plan
terraform apply

# Deploy to production (requires alert_email)
cd ../prod
terraform init
terraform plan -var="alert_email=sre-team@company.com"
terraform apply -var="alert_email=sre-team@company.com"
```

### Key Terraform Concepts Demonstrated

- **Modules** — Reusable, composable infrastructure components
- **Remote State** — S3 backend with DynamoDB locking
- **Workspaces** — Environment isolation (alternative to directories)
- **Data Sources** — Dynamic AMI lookup (`aws_ami`)
- **Dynamic Blocks** — Conditional resource creation
- **Lifecycle Rules** — `create_before_destroy` for zero-downtime
- **Tagging Strategy** — Consistent tags via `default_tags` and `merge()`

---

## Ansible Deep Dive

### Roles

| Role | Purpose | Key Tasks |
|------|---------|-----------|
| **common** | Base server setup | System updates, packages, NTP, sysctl tuning, file limits |
| **docker** | Container runtime | Docker CE install, daemon.json config, log rotation |
| **monitoring** | Observability agents | Node Exporter (Prometheus), CloudWatch Agent |
| **hardening** | Security compliance | SSH hardening, firewalld, kernel params, audit logging |

### Running Playbooks

```bash
cd ansible

# Full server provisioning
ansible-playbook playbooks/site.yml

# Only configure webservers
ansible-playbook playbooks/site.yml --limit webservers

# Only run hardening tasks
ansible-playbook playbooks/site.yml --tags hardening

# Dry run (check mode)
ansible-playbook playbooks/site.yml --check --diff

# Deploy application version 1.2.3
ansible-playbook playbooks/deploy-app.yml -e "app_version=1.2.3"

# Run security audit
ansible-playbook playbooks/security-audit.yml
```

### Key Ansible Concepts Demonstrated

- **Roles** — Modular, reusable configuration units
- **Templates** (Jinja2) — Dynamic config files with variables
- **Handlers** — Service restarts triggered only on changes
- **Tags** — Run specific subsets of tasks
- **Serial** — Rolling deployments (one host at a time)
- **Check Mode** — Dry run without making changes
- **Idempotency** — Safe to run multiple times

---

## The IaC Workflow

```
1. Code → 2. Review → 3. Plan → 4. Apply → 5. Configure → 6. Deploy

1. Write Terraform + Ansible code
2. Code review (PR)
3. terraform plan (preview changes)
4. terraform apply (create infrastructure)
5. ansible-playbook site.yml (configure servers)
6. ansible-playbook deploy-app.yml (deploy application)
```

---

## References

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks)
- [Google SRE Book — Managing Infrastructure](https://sre.google/sre-book/evolving-sre-engagement-model/)

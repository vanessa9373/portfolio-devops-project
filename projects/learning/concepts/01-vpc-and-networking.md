# Concept 1: VPC & Networking

## What is a VPC?

A **Virtual Private Cloud (VPC)** is your own isolated section of the AWS cloud. Think of it as renting a private office floor in a skyscraper — the building (AWS infrastructure) is shared, but your floor is walled off and only accessible to your team.

Every resource you create in AWS (EC2, Aurora, Lambda in a VPC) lives inside a VPC. You control:
- What IP addresses your resources get
- Which resources can talk to each other
- What traffic can enter from the internet
- What traffic can leave to the internet

---

## Subnets — Dividing Your VPC

A **subnet** is a range of IP addresses within your VPC. You assign resources to subnets.

### The Two Types

| Subnet Type | Connected To | Can reach internet? | Use for |
|-------------|-------------|---------------------|---------|
| **Public** | Internet Gateway | Yes (directly) | Load balancers, NAT Gateways, bastion hosts |
| **Private** | NAT Gateway only | Yes (via NAT, outbound only) | EC2 app servers, Lambda, databases |

### The Three-Tier Pattern (used in Projects 1 and 6)

```
Internet
    │
    ▼
Public Subnet (10.0.1.0/24)      ← ALB, NAT Gateway live here
    │
    ▼
Private App Subnet (10.0.11.0/24) ← EC2 API servers, Lambda live here
    │
    ▼
Private Data Subnet (10.0.21.0/24) ← Aurora, ElastiCache live here
```

**Why three tiers?**
- Databases should NEVER be directly reachable from the internet — even accidentally
- App servers shouldn't be reachable directly either — only through the load balancer
- If an app server is compromised, the attacker still can't reach the database (different subnet, different security group)

### CIDR Notation Quick Guide

`10.0.1.0/24` means:
- Network: `10.0.1.x`
- Available IPs: 10.0.1.0 → 10.0.1.255 = 256 addresses (AWS reserves 5, so 251 usable)
- `/16` = 65,536 addresses (VPC level — the whole office building)
- `/24` = 256 addresses (subnet level — one floor)

---

## Internet Gateway vs NAT Gateway

### Internet Gateway (IGW)
- Attached to the VPC, not a subnet
- Allows **bidirectional** internet traffic for resources with public IPs
- Free — no data processing charge
- Used by: public subnets (ALB receives inbound traffic through IGW)

### NAT Gateway
- Lives in a **public subnet**
- Allows private subnet resources to make **outbound** internet requests only
- Inbound connections from the internet are NOT possible through NAT
- Cost: ~$0.045/hr + $0.045/GB processed
- Why one per AZ? If the AZ hosting the NAT fails, private subnets in other AZs lose internet

```
Private EC2 → NAT Gateway (public subnet) → Internet Gateway → Internet
                                           ↑
                              Response comes back same path
```

---

## Security Groups vs NACLs

### Security Groups (SG) — Used in All Projects

Security groups are **stateful firewalls** attached to resources (EC2, RDS, Lambda ENI).

**Stateful** means: if you allow inbound port 443, the response automatically goes back out — you don't need an outbound rule for it.

```
# Example: ALB security group
Inbound:  443 from 0.0.0.0/0 (internet)
Outbound: 8080 to EC2 security group
```

**Key concept: SG chaining (zero-trust)**
Instead of allowing "10.0.0.0/8" (all private IPs), reference another SG:

```
EC2 SG rule: Allow 3306 from aurora-sg
Aurora SG rule: Allow 3306 from ec2-sg
```

This means only EC2 instances with the EC2 security group can reach Aurora — not any random resource in the VPC.

### NACLs — Network Access Control Lists

NACLs are **stateless** firewalls at the subnet level.

**Stateless** means: you need explicit rules for both inbound AND outbound traffic, including ephemeral ports (1024-65535) for responses.

| Feature | Security Group | NACL |
|---------|---------------|------|
| Applied to | Resource (EC2, RDS) | Subnet |
| Stateful? | Yes | No |
| Default | Deny all inbound | Allow all |
| Rule evaluation | All rules evaluated | Rules evaluated in order (lowest # first) |
| Use case | Primary defense layer | Subnet-level block list |

**In practice:** Security groups handle 95% of access control. NACLs add a secondary layer (e.g., block a known malicious IP at the subnet level).

---

## Route Tables

A **route table** is a set of rules that determines where network traffic goes.

```
Public subnet route table:
  10.0.0.0/16  →  local (VPC traffic stays internal)
  0.0.0.0/0    →  igw-xxx (everything else → internet)

Private app subnet route table:
  10.0.0.0/16  →  local
  0.0.0.0/0    →  nat-xxx (outbound via NAT)

Private data subnet route table:
  10.0.0.0/16  →  local
  (no internet route — data tier cannot reach internet)
```

---

## VPC Endpoints — Keeping Traffic Off the Internet

By default, AWS SDK calls from your EC2 instance go: EC2 → NAT → Internet → AWS API.

This means:
1. You pay NAT data processing fees
2. Traffic leaves your VPC
3. Latency is higher

**VPC Endpoints** create a private connection from your VPC directly to AWS services.

### Gateway Endpoints (Free)
- S3 and DynamoDB only
- Add a route in your route table: `s3.amazonaws.com → vpce-xxx`
- No ENI, no cost, no data processing charges

### Interface Endpoints (Paid ~$0.01/hr + $0.01/GB)
- All other AWS services: Secrets Manager, SQS, Kinesis, etc.
- Creates an ENI in your subnet with a private IP
- Traffic stays inside AWS backbone

**Used in:** Projects 1, 5, 6 — S3 and DynamoDB Gateway endpoints eliminate NAT costs for high-volume S3 reads.

---

## Multi-AZ Design — Why It Matters

An **Availability Zone (AZ)** is a physically separate data center within a region. AZs in the same region are connected by high-speed fiber but are far enough apart to be isolated from each other's power, cooling, and network failures.

```
us-east-1a        us-east-1b        us-east-1c
┌──────────┐     ┌──────────┐     ┌──────────┐
│ Public   │     │ Public   │     │ Public   │
│ Subnet   │     │ Subnet   │     │ Subnet   │
│ (ALB)    │     │ (ALB)    │     │ (ALB)    │
├──────────┤     ├──────────┤     ├──────────┤
│ Private  │     │ Private  │     │ Private  │
│ App      │     │ App      │     │ App      │
│ (EC2)    │     │ (EC2)    │     │ (EC2)    │
├──────────┤     ├──────────┤     ├──────────┤
│ Private  │     │ Private  │     │ Private  │
│ Data     │     │ Data     │     │ Data     │
│ (Aurora) │     │ (Aurora) │     │ (Aurora) │
└──────────┘     └──────────┘     └──────────┘
```

If us-east-1a has a power outage: traffic automatically shifts to 1b and 1c. Aurora promotes a replica. The ALB stops sending to unhealthy 1a targets. **Zero customer impact.**

---

## VPC Flow Logs

**What:** Captures metadata about all IP traffic in/out of your VPC.  
**What it logs:** Source IP, destination IP, port, protocol, bytes, packets, action (ACCEPT/REJECT)  
**What it does NOT log:** Packet contents (not a packet capture)

**Use cases:**
- Security: detect port scanning, unexpected connection attempts
- Debugging: "why can't my Lambda reach the database?"
- Compliance: evidence that access was restricted

**Cost:** ~$0.50/GB ingested into CloudWatch Logs. In Projects 1 and 6, logs go to CloudWatch with 30-day retention.

---

## Interview Questions for This Concept

**Q: What's the difference between a public and private subnet?**
> A public subnet has a route to an Internet Gateway, so resources with public IPs can receive inbound internet traffic. A private subnet routes outbound traffic through a NAT Gateway — resources can initiate internet connections (e.g., to download packages) but cannot receive inbound connections from the internet.

**Q: Why do you use a NAT Gateway per AZ instead of one shared NAT?**
> If you use one NAT in us-east-1a and that AZ goes down, all private subnets in other AZs lose internet access. One NAT per AZ costs more (~$45/AZ/month) but eliminates this cross-AZ failure dependency.

**Q: What's the difference between a security group and a NACL?**
> Security groups are stateful and applied to resources — if you allow inbound port 443, responses automatically go out. NACLs are stateless and applied to subnets — you need explicit rules for both directions. In practice, security groups handle primary access control; NACLs add a subnet-level block list as a secondary layer.

**Q: What is a VPC endpoint and why would you use one?**
> A VPC endpoint creates a private connection from your VPC to AWS services without traffic leaving the AWS network. Gateway endpoints (S3 and DynamoDB) are free. Interface endpoints for other services cost ~$0.01/hr. You use them to eliminate NAT data processing costs (at 1TB/month, a gateway endpoint saves ~$45/month vs NAT), reduce latency, and improve security by keeping traffic off the public internet.

# Interview Guide — How to Present This Project

## 30-Second Elevator Pitch

> "I deployed a production-grade microservices ecommerce platform on AWS EKS
> using modern DevOps practices. The system runs 11 containerised services
> managed by Kubernetes, with a fully automated CI/CD pipeline using GitHub
> Actions, GitOps deployment via ArgoCD, complete observability with Prometheus
> and Grafana, and all infrastructure defined in Terraform. The architecture
> is multi-AZ, self-healing, and auto-scales based on real traffic."

---

## Architecture Walkthrough (2-3 minutes)

**Opening:**
> "Let me walk you through the architecture. Traffic enters through Route 53,
> hits an Application Load Balancer, and is routed to our EKS cluster running
> in private subnets across three availability zones."

**Application layer:**
> "The application is the Google Online Boutique — an open-source ecommerce
> platform with 11 microservices. Each service is a separate container with its
> own Kubernetes Deployment, Service, resource limits, health checks, and
> autoscaler. They communicate over gRPC internally — no traffic leaves the
> cluster for service-to-service calls."

**Infrastructure:**
> "All infrastructure is defined in Terraform — VPC, subnets, EKS cluster,
> ECR repositories, IAM roles. I can tear down and recreate the entire
> environment from a single `terraform apply`. Nothing is click-ops."

**CI/CD:**
> "When I push code to main, GitHub Actions builds the Docker images, runs
> Trivy security scans, and pushes them to ECR. Then it updates the image tags
> in the Kubernetes manifests in Git. ArgoCD — running inside the cluster —
> detects that Git changed and automatically syncs the new manifests. This is
> GitOps: Git is the single source of truth for what runs in production."

**Observability:**
> "Prometheus scrapes metrics from all pods every 15 seconds. Grafana
> visualises those as dashboards. Alert rules fire when error rates spike,
> pods crash loop, or memory is near OOM. CloudWatch captures all application
> logs and I can query them with CloudWatch Insights."

**Security:**
> "No AWS access keys exist anywhere in the cluster. Pods use IRSA — IAM
> Roles for Service Accounts — to get temporary, auto-rotating credentials.
> All secrets are in AWS Secrets Manager. Kubernetes RBAC restricts what
> each service account can do. Network Policies restrict pod-to-pod traffic
> to only what is explicitly needed."

---

## Common Interview Questions

**Q: Why Kubernetes instead of just ECS?**
> "EKS gives you a standard, portable platform. The same Kubernetes YAML
> runs on any cloud or on-premises. It also has a richer ecosystem —
> ArgoCD, Prometheus Operator, Karpenter — tools that integrate natively.
> ECS is simpler but AWS-specific."

**Q: How do you handle a failed deployment?**
> "ArgoCD makes rollback a single command: `argocd app rollback online-boutique 1`.
> It reverts the manifests to the previous Git commit and Kubernetes does a
> rolling update back to the old version. For production, I also configure
> CodeDeploy-style canary deployments where we send 10% of traffic to the
> new version, monitor for 5 minutes, then cut over fully — or auto-rollback
> if error rate exceeds threshold."

**Q: How does the application scale under load?**
> "Two layers. The HPA watches CPU and memory on each pod. When frontend
> hits 60% CPU, it adds more pod replicas within 60 seconds. When existing
> nodes are full, Karpenter automatically launches new EC2 nodes in about
> 2 minutes. When traffic drops, Karpenter consolidates workloads onto fewer
> nodes and removes the empty ones — so we're only paying for what we use."

**Q: How do you manage secrets?**
> "Everything sensitive is in AWS Secrets Manager. The External Secrets
> Operator runs in the cluster and syncs those values into Kubernetes
> Secrets automatically. Rotation is handled by Secrets Manager on a
> 30-day schedule. Nothing is hardcoded in code or committed to Git."

**Q: What happens if an availability zone goes down?**
> "The application keeps running. EKS worker nodes are spread across three
> AZs. The ALB stops routing to the failed AZ automatically. Pod anti-affinity
> rules ensure replicas are spread across AZs, so losing one AZ doesn't take
> down all replicas of a service. Pod Disruption Budgets ensure at least
> one replica is always available during planned disruptions like node upgrades."

**Q: How much does this cost to run?**
> "About $300 per month with three t3.medium nodes. In a real production
> environment, we'd use Spot instances for worker nodes which cuts that by
> 70%. We'd also use AWS Savings Plans for a 1-year commitment to save
> another 40%. For this portfolio, I scale nodes to zero when not demoing
> to minimise cost."

---

## Business Value to Highlight

| Technical Practice | Business Value |
|---|---|
| Infrastructure as Code (Terraform) | Environments reproduced in minutes, not days |
| CI/CD automation | Features ship in 15 minutes instead of hours |
| GitOps (ArgoCD) | Full audit trail of every production change |
| Auto-scaling (HPA + Karpenter) | Handle 10x traffic spikes without manual intervention |
| Multi-AZ deployment | 99.9% uptime SLA achievable |
| Observability stack | Mean time to detect and resolve incidents reduced by 80% |
| Security scanning | Vulnerabilities caught before they reach production |
| Secrets management | Zero credential exposure incidents |

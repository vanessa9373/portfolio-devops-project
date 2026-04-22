#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# install-tools.sh — Install all DevOps tools needed for this project
# Supports: macOS (Homebrew) and Ubuntu/Debian Linux
# Usage: chmod +x scripts/setup/install-tools.sh && ./scripts/setup/install-tools.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓] $*${NC}"; }
warn() { echo -e "${YELLOW}[!] $*${NC}"; }

OS=$(uname -s)
ARCH=$(uname -m)

echo "======================================"
echo " Portfolio DevOps — Tool Installer"
echo " OS: $OS | ARCH: $ARCH"
echo "======================================"
echo ""

# ─── AWS CLI ────────────────────────────────────────────────────────────────
install_awscli() {
  if command -v aws &>/dev/null; then
    warn "AWS CLI already installed: $(aws --version)"
    return
  fi
  log "Installing AWS CLI..."
  if [ "$OS" = "Darwin" ]; then
    curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg
    sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
  else
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp
    sudo /tmp/aws/install
  fi
  log "AWS CLI installed: $(aws --version)"
}

# ─── KUBECTL ────────────────────────────────────────────────────────────────
install_kubectl() {
  if command -v kubectl &>/dev/null; then
    warn "kubectl already installed: $(kubectl version --client --short 2>/dev/null | head -1)"
    return
  fi
  log "Installing kubectl..."
  KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
  if [ "$OS" = "Darwin" ]; then
    curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/darwin/amd64/kubectl"
  else
    curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  fi
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
  log "kubectl installed: $(kubectl version --client --short 2>/dev/null | head -1)"
}

# ─── TERRAFORM ──────────────────────────────────────────────────────────────
install_terraform() {
  if command -v terraform &>/dev/null; then
    warn "Terraform already installed: $(terraform version | head -1)"
    return
  fi
  log "Installing Terraform..."
  if [ "$OS" = "Darwin" ]; then
    brew tap hashicorp/tap
    brew install hashicorp/tap/terraform
  else
    wget -qO- https://apt.releases.hashicorp.com/gpg | \
      gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
      https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
      sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt-get update -q && sudo apt-get install -y terraform
  fi
  log "Terraform installed: $(terraform version | head -1)"
}

# ─── DOCKER ─────────────────────────────────────────────────────────────────
install_docker() {
  if command -v docker &>/dev/null; then
    warn "Docker already installed: $(docker --version)"
    return
  fi
  log "Installing Docker..."
  if [ "$OS" = "Darwin" ]; then
    warn "Please install Docker Desktop from https://www.docker.com/products/docker-desktop/"
  else
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    sudo systemctl enable docker
    sudo systemctl start docker
  fi
  log "Docker installed: $(docker --version 2>/dev/null || echo 'restart shell to use docker')"
}

# ─── HELM ───────────────────────────────────────────────────────────────────
install_helm() {
  if command -v helm &>/dev/null; then
    warn "Helm already installed: $(helm version --short)"
    return
  fi
  log "Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  log "Helm installed: $(helm version --short)"
}

# ─── EKSCTL ─────────────────────────────────────────────────────────────────
install_eksctl() {
  if command -v eksctl &>/dev/null; then
    warn "eksctl already installed: $(eksctl version)"
    return
  fi
  log "Installing eksctl..."
  if [ "$OS" = "Darwin" ]; then
    brew tap weaveworks/tap
    brew install weaveworks/tap/eksctl
  else
    EKSCTL_VERSION=$(curl -sL https://api.github.com/repos/weaveworks/eksctl/releases/latest \
      | grep tag_name | cut -d'"' -f4)
    curl -sL "https://github.com/weaveworks/eksctl/releases/download/${EKSCTL_VERSION}/eksctl_Linux_amd64.tar.gz" \
      | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin/
  fi
  log "eksctl installed: $(eksctl version)"
}

# ─── ARGOCD CLI ─────────────────────────────────────────────────────────────
install_argocd_cli() {
  if command -v argocd &>/dev/null; then
    warn "argocd CLI already installed: $(argocd version --client --short 2>/dev/null | head -1)"
    return
  fi
  log "Installing ArgoCD CLI..."
  ARGOCD_VERSION=$(curl -sL https://api.github.com/repos/argoproj/argo-cd/releases/latest \
    | grep tag_name | cut -d'"' -f4)
  if [ "$OS" = "Darwin" ]; then
    curl -sSL -o /tmp/argocd \
      "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-darwin-amd64"
  else
    curl -sSL -o /tmp/argocd \
      "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
  fi
  chmod +x /tmp/argocd
  sudo mv /tmp/argocd /usr/local/bin/
  log "ArgoCD CLI installed: $(argocd version --client --short 2>/dev/null | head -1)"
}

# ─── TRIVY ──────────────────────────────────────────────────────────────────
install_trivy() {
  if command -v trivy &>/dev/null; then
    warn "Trivy already installed: $(trivy --version | head -1)"
    return
  fi
  log "Installing Trivy..."
  if [ "$OS" = "Darwin" ]; then
    brew install aquasecurity/trivy/trivy
  else
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | \
      sh -s -- -b /usr/local/bin
  fi
  log "Trivy installed: $(trivy --version | head -1)"
}

# ─── GIT ────────────────────────────────────────────────────────────────────
install_git() {
  if command -v git &>/dev/null; then
    warn "Git already installed: $(git --version)"
    return
  fi
  log "Installing Git..."
  if [ "$OS" = "Darwin" ]; then
    xcode-select --install 2>/dev/null || brew install git
  else
    sudo apt-get install -y git
  fi
  log "Git installed: $(git --version)"
}

# ─── RUN ALL ────────────────────────────────────────────────────────────────
install_git
install_awscli
install_kubectl
install_terraform
install_docker
install_helm
install_eksctl
install_argocd_cli
install_trivy

echo ""
echo "======================================"
echo " All tools installed successfully!"
echo "======================================"
echo ""
echo "Next steps:"
echo "  1. Run: aws configure"
echo "  2. Run: cd terraform && terraform init"
echo "  3. Run: ./scripts/setup/bootstrap.sh"

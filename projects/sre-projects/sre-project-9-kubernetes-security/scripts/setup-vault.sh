#!/usr/bin/env bash
##############################################################################
# setup-vault.sh — Install and configure HashiCorp Vault on Kubernetes
#
# Steps:
# 1. Install Vault via Helm
# 2. Initialize and unseal (or auto-unseal via KMS)
# 3. Enable K8s auth method
# 4. Create policies and roles
# 5. Store initial secrets
##############################################################################
set -euo pipefail

VAULT_NAMESPACE=${VAULT_NAMESPACE:-vault}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "================================================================"
echo "  Vault Setup"
echo "  Namespace: $VAULT_NAMESPACE"
echo "================================================================"
echo ""

# ── 1. Add Helm repo and install ───────────────────────────────────────
echo "[1/6] Installing Vault via Helm..."
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update

kubectl create namespace "$VAULT_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install vault hashicorp/vault \
  --namespace "$VAULT_NAMESPACE" \
  --values "$PROJECT_DIR/vault/vault-install.yaml" \
  --wait --timeout 5m

echo "Vault pods:"
kubectl get pods -n "$VAULT_NAMESPACE" -l app.kubernetes.io/name=vault
echo ""

# ── 2. Initialize Vault ────────────────────────────────────────────────
echo "[2/6] Initializing Vault..."
INIT_STATUS=$(kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- vault status -format=json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('initialized', False))" 2>/dev/null || echo "false")

if [ "$INIT_STATUS" = "False" ] || [ "$INIT_STATUS" = "false" ]; then
  echo "  Vault not initialized. Initializing with 5 key shares, 3 threshold..."
  kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- vault operator init \
    -key-shares=5 -key-threshold=3 -format=json > /tmp/vault-init.json

  echo "  CRITICAL: Save these unseal keys securely!"
  echo "  Init output saved to /tmp/vault-init.json"
  echo "  Root token: $(python3 -c "import json; print(json.load(open('/tmp/vault-init.json'))['root_token'])")"
  echo ""

  # Auto-unseal the first pod (for dev/testing only)
  for i in 0 1 2; do
    KEY=$(python3 -c "import json; print(json.load(open('/tmp/vault-init.json'))['unseal_keys_b64'][$i])")
    kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- vault operator unseal "$KEY"
  done
  echo "  Vault unsealed."
else
  echo "  Vault already initialized."
fi
echo ""

# ── 3. Enable KV secrets engine ────────────────────────────────────────
echo "[3/6] Enabling secrets engines..."
ROOT_TOKEN=$(python3 -c "import json; print(json.load(open('/tmp/vault-init.json'))['root_token'])" 2>/dev/null || echo "")

if [ -n "$ROOT_TOKEN" ]; then
  kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- sh -c "
    export VAULT_TOKEN='$ROOT_TOKEN'
    vault secrets enable -version=2 -path=secret kv 2>/dev/null || echo 'KV engine already enabled'
    vault audit enable file file_path=/vault/audit/audit.log 2>/dev/null || echo 'Audit already enabled'
  "
  echo "  KV v2 secrets engine enabled."
  echo "  Audit logging enabled."
fi
echo ""

# ── 4. Enable K8s auth method ──────────────────────────────────────────
echo "[4/6] Configuring Kubernetes auth..."
if [ -n "$ROOT_TOKEN" ]; then
  kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- sh -c "
    export VAULT_TOKEN='$ROOT_TOKEN'
    vault auth enable kubernetes 2>/dev/null || echo 'K8s auth already enabled'
    vault write auth/kubernetes/config \
      kubernetes_host=https://\${KUBERNETES_SERVICE_HOST}:\${KUBERNETES_SERVICE_PORT}
  "
  echo "  Kubernetes auth method configured."
fi
echo ""

# ── 5. Create policies ─────────────────────────────────────────────────
echo "[5/6] Creating Vault policies..."
if [ -n "$ROOT_TOKEN" ]; then
  # Copy policies into the pod and apply
  kubectl cp "$PROJECT_DIR/vault/vault-policies.hcl" \
    "$VAULT_NAMESPACE/vault-0:/tmp/app-readonly.hcl"

  kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- sh -c "
    export VAULT_TOKEN='$ROOT_TOKEN'
    vault policy write app-readonly /tmp/app-readonly.hcl
  "
  echo "  Policies created: app-readonly"
fi
echo ""

# ── 6. Create K8s auth roles ───────────────────────────────────────────
echo "[6/6] Creating auth roles..."
if [ -n "$ROOT_TOKEN" ]; then
  for ENV in production staging; do
    kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- sh -c "
      export VAULT_TOKEN='$ROOT_TOKEN'
      vault write auth/kubernetes/role/${ENV}-app \
        bound_service_account_names=app-vault-sa \
        bound_service_account_namespaces=${ENV} \
        policies=app-readonly \
        ttl=1h
    "
    echo "  Role created: ${ENV}-app"
  done
fi

echo ""
echo "================================================================"
echo "  Vault Setup Complete!"
echo ""
echo "  Access UI: kubectl port-forward svc/vault -n $VAULT_NAMESPACE 8200:8200"
echo "  URL: https://localhost:8200"
echo ""
echo "  Store a secret:"
echo "    vault kv put secret/production/database host=db.internal password=s3cur3"
echo ""
echo "  Test K8s auth:"
echo "    kubectl run test --image=vault -n production --restart=Never -- \\"
echo "      vault login -method=kubernetes role=production-app"
echo "================================================================"

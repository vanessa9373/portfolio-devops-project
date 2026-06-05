##############################################################################
# Vault Policies — Least-privilege access to secrets
#
# Policies:
# - app-readonly:   Read secrets for application workloads
# - app-admin:      Manage secrets for a specific app path
# - platform-admin: Full access for SRE team
# - ci-pipeline:    Limited access for CI/CD to read deploy secrets
##############################################################################

# ── Application Read-Only ───────────────────────────────────────────────
# Attached to K8s service accounts via auth method
path "secret/data/{{identity.entity.metadata.namespace}}/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/{{identity.entity.metadata.namespace}}/*" {
  capabilities = ["list"]
}

# Allow reading database credentials
path "database/creds/{{identity.entity.metadata.namespace}}-*" {
  capabilities = ["read"]
}

# ── Application Admin ──────────────────────────────────────────────────
# For team leads who manage their app's secrets
# Save as: app-admin.hcl
/*
path "secret/data/{{identity.entity.metadata.namespace}}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/{{identity.entity.metadata.namespace}}/*" {
  capabilities = ["read", "list", "delete"]
}

path "secret/delete/{{identity.entity.metadata.namespace}}/*" {
  capabilities = ["update"]
}

path "secret/undelete/{{identity.entity.metadata.namespace}}/*" {
  capabilities = ["update"]
}
*/

# ── Platform Admin (SRE Team) ──────────────────────────────────────────
# Save as: platform-admin.hcl
/*
# Full secret management
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage auth methods
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Manage policies
path "sys/policies/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# View audit logs
path "sys/audit" {
  capabilities = ["read", "list"]
}

path "sys/audit/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Manage secret engines
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Health and status
path "sys/health" {
  capabilities = ["read"]
}

path "sys/seal-status" {
  capabilities = ["read"]
}
*/

# ── CI/CD Pipeline ─────────────────────────────────────────────────────
# Save as: ci-pipeline.hcl
/*
# Read deploy-related secrets only
path "secret/data/ci/*" {
  capabilities = ["read", "list"]
}

# Read container registry credentials
path "secret/data/registry/*" {
  capabilities = ["read"]
}

# Read TLS certificates for deployments
path "pki/issue/internal" {
  capabilities = ["create", "update"]
}

# Deny everything else explicitly
path "secret/data/production/*" {
  capabilities = ["deny"]
}
*/

#!/bin/bash
##############################################################################
# Validate All Terraform & Ansible Configurations
#
# Run this before committing to catch syntax errors and formatting issues.
#
# Usage:
#   ./validate-all.sh
##############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

PASS=0
FAIL=0

check() {
    local label="$1"
    shift
    echo -n "  Checking $label... "
    if "$@" > /dev/null 2>&1; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        FAIL=$((FAIL + 1))
    fi
}

echo "============================================"
echo "  Infrastructure Validation"
echo "============================================"
echo ""

# ── Terraform Checks ──────────────────────────────────────────────────
echo "Terraform:"

for env in dev staging prod; do
    ENV_DIR="$PROJECT_DIR/terraform/environments/$env"
    if [ -d "$ENV_DIR" ]; then
        check "$env — format" terraform fmt -check -recursive "$ENV_DIR"
        check "$env — validate" bash -c "cd $ENV_DIR && terraform init -backend=false > /dev/null 2>&1 && terraform validate"
    fi
done

echo ""

# ── Ansible Checks ─────────────────────────────────────────────────────
echo "Ansible:"

ANSIBLE_DIR="$PROJECT_DIR/ansible"

check "inventory syntax" ansible-inventory -i "$ANSIBLE_DIR/inventory/hosts.yml" --list
check "site.yml syntax" ansible-playbook "$ANSIBLE_DIR/playbooks/site.yml" --syntax-check
check "deploy-app.yml syntax" ansible-playbook "$ANSIBLE_DIR/playbooks/deploy-app.yml" --syntax-check
check "security-audit.yml syntax" ansible-playbook "$ANSIBLE_DIR/playbooks/security-audit.yml" --syntax-check

if command -v ansible-lint > /dev/null 2>&1; then
    check "ansible-lint" ansible-lint "$ANSIBLE_DIR/playbooks/" "$ANSIBLE_DIR/roles/"
fi

echo ""
echo "============================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

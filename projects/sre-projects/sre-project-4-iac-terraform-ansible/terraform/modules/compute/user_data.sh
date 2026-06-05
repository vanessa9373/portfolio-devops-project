#!/bin/bash
##############################################################################
# EC2 User Data — Bootstrap script for application instances
# This runs on first boot to configure the instance.
##############################################################################
set -euo pipefail

# Log everything for debugging
exec > >(tee /var/log/user-data.log) 2>&1
echo "=== User data script started at $(date) ==="

# ── System Updates ──────────────────────────────────────────────────────
echo "[1/5] Updating system packages..."
dnf update -y

# ── Install Docker ──────────────────────────────────────────────────────
echo "[2/5] Installing Docker..."
dnf install -y docker
systemctl enable docker
systemctl start docker

# ── Install CloudWatch Agent ────────────────────────────────────────────
echo "[3/5] Installing CloudWatch Agent..."
dnf install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<'CWCONFIG'
{
  "metrics": {
    "namespace": "${project_name}/${environment}",
    "metrics_collected": {
      "cpu": { "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"], "totalcpu": true },
      "mem": { "measurement": ["mem_used_percent"] },
      "disk": { "measurement": ["disk_used_percent"], "resources": ["*"] }
    },
    "append_dimensions": {
      "InstanceId": "$${aws:InstanceId}",
      "Environment": "${environment}"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/*.log",
            "log_group_name": "/${project_name}/${environment}/app",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 30
          }
        ]
      }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

# ── Install Node Exporter (Prometheus) ──────────────────────────────────
echo "[4/5] Installing Node Exporter..."
useradd --no-create-home --shell /bin/false node_exporter || true

NODE_EXPORTER_VERSION="1.7.0"
curl -sLO "https://github.com/prometheus/node_exporter/releases/download/v$${NODE_EXPORTER_VERSION}/node_exporter-$${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar xzf "node_exporter-$${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
cp "node_exporter-$${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

cat > /etc/systemd/system/node_exporter.service <<'SERVICE'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# ── Create Application Directory ────────────────────────────────────────
echo "[5/5] Setting up application directory..."
mkdir -p /var/log/app /opt/app
echo '{"status": "healthy", "environment": "${environment}"}' > /opt/app/health.json

echo "=== User data script completed at $(date) ==="

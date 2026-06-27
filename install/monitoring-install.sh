#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jakov Petrina (jpetrina)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://prometheus.io/ | https://grafana.com/ | https://github.com/prometheus-pve/prometheus-pve-exporter

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# --- Prometheus ---
fetch_and_deploy_gh_release "prometheus" "prometheus/prometheus" "prebuild" "latest" "/usr/local/bin" "*linux-$(arch_resolve).tar.gz"

msg_info "Installing Prometheus"
mkdir -p /etc/prometheus
mkdir -p /var/lib/prometheus
mv /usr/local/bin/prometheus.yml /etc/prometheus/prometheus.yml 2>/dev/null || true
msg_ok "Installed Prometheus"

msg_info "Creating Prometheus Service"
cat <<'EOF' >/etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=root
Restart=always
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/ \
    --web.listen-address=0.0.0.0:9090
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now prometheus
msg_ok "Created Prometheus Service"

# --- Grafana ---
msg_info "Installing Dependencies"
$STD apt install -y apt-transport-https
msg_ok "Installed Dependencies"

msg_info "Setting up Grafana Repository"
setup_deb822_repo \
  "grafana" \
  "https://apt.grafana.com/gpg.key" \
  "https://apt.grafana.com" \
  "stable" \
  "main"
msg_ok "Grafana Repository setup successfully"

msg_info "Installing Grafana"
$STD apt install -y grafana
systemctl enable -q --now grafana-server
msg_ok "Installed Grafana"

# --- Prometheus PVE Exporter ---
PYTHON_VERSION="3.12" setup_uv

msg_info "Installing Prometheus Proxmox VE Exporter"
mkdir -p /opt/prometheus-pve-exporter
cd /opt/prometheus-pve-exporter

$STD uv venv --clear /opt/prometheus-pve-exporter/.venv
$STD /opt/prometheus-pve-exporter/.venv/bin/python -m ensurepip --upgrade
$STD /opt/prometheus-pve-exporter/.venv/bin/python -m pip install --upgrade pip
$STD /opt/prometheus-pve-exporter/.venv/bin/python -m pip install prometheus-pve-exporter

cat <<EOF >/opt/prometheus-pve-exporter/pve.yml
default:
    user: prometheus@pve
    password: sEcr3T!
    verify_ssl: false
EOF
msg_ok "Installed Prometheus Proxmox VE Exporter"

msg_info "Creating PVE Exporter Service"
cat <<EOF >/etc/systemd/system/prometheus-pve-exporter.service
[Unit]
Description=Prometheus Proxmox VE Exporter
Documentation=https://github.com/znerol/prometheus-pve-exporter
After=syslog.target network.target

[Service]
User=root
Restart=always
Type=simple
ExecStart=/opt/prometheus-pve-exporter/.venv/bin/pve_exporter \\
    --config.file=/opt/prometheus-pve-exporter/pve.yml \\
    --web.listen-address=0.0.0.0:9221
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now prometheus-pve-exporter
msg_ok "Created PVE Exporter Service"

motd_ssh
customize
cleanup_lxc

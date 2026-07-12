#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jakov Petrina (jpetrina)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/akpw/mktxp

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PYTHON_VERSION="3.12" setup_uv

msg_info "Installing MKTXP Exporter"
mkdir -p /opt/mktxp
cd /opt/mktxp

$STD uv venv --clear /opt/mktxp/.venv
$STD /opt/mktxp/.venv/bin/python -m ensurepip --upgrade
$STD /opt/mktxp/.venv/bin/python -m pip install --upgrade pip
$STD /opt/mktxp/.venv/bin/python -m pip install mktxp

sudo -u root -i bash -c 'MKTXP_HOME=/opt/mktxp mktxp edit -ed true' 2>/dev/null
[[ ! -f /opt/mktxp/mktxp.conf ]] && sudo -u root cp /opt/mktxp/.venv/lib/python*/site-packages/mktxp/default_mktxp.conf /opt/mktxp/mktxp.conf 2>/dev/null || true
msg_ok "Installed MKTXP Exporter"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/mktxp.service
[Unit]
Description=MKTXP Mikrotik Exporter to Prometheus
Documentation=https://github.com/akpw/mktxp
After=syslog.target network.target

[Service]
User=root
Restart=always
Type=simple
Environment=MKTXP_HOME=/opt/mktxp
ExecStart=/opt/mktxp/.venv/bin/mktxp --cfg-dir /opt/mktxp export
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now mktxp
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc

#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jakov Petrina (jpetrina)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/garybowers/bootimus

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Bootimus"
RELEASE=$(get_latest_github_release "garybowers/bootimus" "false")
ARCH=$(dpkg --print-architecture)
if ! curl -fsSL "https://github.com/garybowers/bootimus/releases/download/${RELEASE}/bootimus-linux-${ARCH}" -o /usr/local/bin/bootimus; then
  msg_error "Failed to download Bootimus binary"
  exit 1
fi
$STD chmod +x /usr/local/bin/bootimus

mkdir -p /etc/bootimus /opt/bootimus/data

cat > /etc/systemd/system/bootimus.service <<EOF
[Unit]
Description=Bootimus PXE/HTTP Boot Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/bootimus serve --data-dir /opt/bootimus/data --proxy-dhcp
Restart=on-failure
RestartSec=5
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q --now bootimus
msg_ok "Setup Bootimus"

for i in $(seq 10); do
  if DATA=$($STD journalctl -u bootimus -b -o cat 2>/dev/null | grep -m 1 'Password'); then break; fi
  sleep 1
done

if [ -n "$DATA" ]; then
    echo -e "Bootimus admin credentials:"
    echo -e "    ${DATA}"
else
    msg_warn "Could not retrieve Bootimus password. Check journalctl -u bootimus for details."
fi

motd_ssh
customize
cleanup_lxc

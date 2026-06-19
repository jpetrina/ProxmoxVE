#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jakov Petrina (jpetrina)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.syncthing.net/users/strelaysrv.html

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_deb822_repo \
  "syncthing" \
  "https://syncthing.net/release-key.gpg" \
  "https://apt.syncthing.net/" \
  "syncthing" \
  "stable-v2"

msg_info "Setting up Syncthing Relay Server"
cat <<EOF >/etc/apt/preferences.d/syncthing
Package: *
Pin: origin apt.syncthing.net
Pin-Priority: 990
EOF
# https://apt.syncthing.net/pool/syncthing-relaysrv_X.Y.Z_amd64.deb
$STD apt install -y syncthing-relaysrv

cat > /etc/default/syncthing-relaysrv <<EOF
# Default settings for syncthing-relaysrv (strelaysrv).
NAT=true
RELAYSRV_OPTS="-listen=:22067 -status-srv=:22070"
EOF

systemctl enable -q --now strelaysrv
msg_ok "Setup Syncthing Relay Server"

sleep 1s

if DATA=$(journalctl -u strelaysrv -b -o cat 2>/dev/null | grep -m 1 -o '\?id=.*' 2>/dev/null); then
    echo -e "Syncthing Relay Server parameters and ID:"
    echo -e "    ${DATA}"
fi

motd_ssh
customize
cleanup_lxc

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

msg_info "Installing Syncthing Relay Server"
$STD apk add --no-cache syncthing-utils

msg_info "Creating Syncthing Relay Server Service"
cat > /etc/init.d/syncthing-relaysrv <<'EOF'
#!/sbin/openrc-run
name="Syncthing Relay"
command="/usr/bin/strelaysrv"
command_args="-listen=:22067 -status-srv=:22070"
command_background="true"
command_user="root"
pidfile="/run/${RC_SVCNAME}.pid"

output_log="/var/log/syncthing-relaysrv.log"
error_log="/var/log/syncthing-relaysrv.err"

depend() {
    need net
}
EOF

chmod +x /etc/init.d/syncthing-relaysrv
$STD rc-update add syncthing-relaysrv default
$STD rc-service syncthing-relaysrv restart || rc-service syncthing-relay start
msg_ok "Started Syncthing Relay Server"

sleep 1s

if DATA=$(egrep -m 1 -o '\?id=.*' /var/log/syncthing-relaysrv.log 2>/dev/null); then
    echo -e "Syncthing Relay Server parameters and ID:"
    echo -e "    ${DATA}"
fi

motd_ssh
customize

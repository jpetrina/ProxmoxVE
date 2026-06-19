#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jakov Petrina (jpetrina)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.syncthing.net/users/strelaysrv.html

APP="Alpine-Syncthing-Relaysrv"
var_tags="${var_tags:-alpine;networking}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-1}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  msg_info "Updating Alpine Packages"
  $STD apk -U upgrade

  msg_info "Updating Syncthing Relay Server"
  $STD apk upgrade syncthing-utils

  msg_info "Restarting Syncthing Relay Server"
  $STD rc-service syncthing-relaysrv restart

  msg_ok "Updated successfully!"
  exit 0
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Relay address:${CL}"
echo -e "${GATEWAY}${BGN}relay://${IP}:22067${CL}"
echo -e "${INFO}${YW}Server status is available as JSON at URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:22070/status${CL}"

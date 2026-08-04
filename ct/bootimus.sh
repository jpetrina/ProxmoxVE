#!/usr/bin/env bash
source ${PWD}/misc/build.func
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jakov Petrina (jpetrina)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/garybowers/bootimus

APP="Bootimus"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_net_bind="${var_net_bind:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -x /usr/local/bin/bootimus ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Bootimus"
  RELEASE=$(get_latest_github_release "garybowers/bootimus" "false")
ARCH=$(dpkg --print-architecture)
if ! curl -fsSL "https://github.com/garybowers/bootimus/releases/download/${RELEASE}/bootimus-linux-${ARCH}" -o /usr/local/bin/bootimus; then
  msg_error "Failed to download Bootimus binary"
  exit 1
fi
$STD chmod +x /usr/local/bin/bootimus

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Admin UI:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8081${CL}"

#!/usr/bin/env bash
source ${PWD}/misc/build.func
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jakov Petrina (jpetrina)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/akpw/mktxp

APP="Prometheus-MKTXP-Exporter"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/mktxp.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop mktxp
  msg_ok "Stopped Service"

  export MKTXP_VENV_PATH="/opt/mktxp/.venv"
  export MKTXP_BIN="${MKTXP_VENV_PATH}/bin/mktxp"

  if [[ ! -d "$MKTXP_VENV_PATH" || ! -x "$MKTXP_BIN" ]]; then
    PYTHON_VERSION="3.12" setup_uv
    msg_info "Migrating to uv/venv"
    rm -rf "$MKTXP_VENV_PATH"
    mkdir -p /opt/mktxp
    cd /opt/mktxp
    $STD uv venv --clear "$MKTXP_VENV_PATH"
    $STD "$MKTXP_VENV_PATH/bin/python" -m ensurepip --upgrade
    $STD "$MKTXP_VENV_PATH/bin/python" -m pip install --upgrade pip
    $STD "$MKTXP_VENV_PATH/bin/python" -m pip install mktxp
    msg_ok "Migrated to uv/venv"
  else
    msg_info "Updating MKTXP Exporter"
    PYTHON_VERSION="3.12" setup_uv
    $STD "$MKTXP_VENV_PATH/bin/python" -m pip install --upgrade mktxp
    msg_ok "Updated MKTXP Exporter"
  fi
  local service_file="/etc/systemd/system/mktxp.service"
  if ! grep -q "${MKTXP_VENV_PATH}/bin/mktxp" "$service_file"; then
    msg_info "Updating systemd service"
    cat <<EOF >"$service_file"
[Unit]
Description=MKTXP Mikrotik Exporter to Prometheus
Documentation=https://github.com/akpw/mktxp
After=syslog.target network.target

[Service]
User=root
Restart=always
Type=simple
ExecStart=${MKTXP_VENV_PATH}/bin/mktxp export
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
    $STD systemctl daemon-reload
    msg_ok "Updated systemd service"
  fi

  msg_info "Starting Service"
  systemctl start mktxp
  msg_ok "Started Service"

  msg_ok "Updated successfully!"
  exit 0
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:49090${CL}"

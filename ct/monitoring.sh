#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jakov Petrina (jpetrina)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://prometheus.io/ | https://grafana.com/ | https://github.com/prometheus-pve/prometheus-pve-exporter

APP="Monitoring"
var_tags="${var_tags:-monitoring;visualization}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
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

  # --- Prometheus ---
  if [[ -f /etc/systemd/system/prometheus.service ]]; then
    if check_for_gh_release "prometheus" "prometheus/prometheus"; then
      msg_info "Updating Prometheus"
      systemctl stop prometheus
      fetch_and_deploy_gh_release "prometheus" "prometheus/prometheus" "prebuild" "latest" "/usr/local/bin" "*linux-$(arch_resolve).tar.gz"
      rm -f /usr/local/bin/prometheus.yml
      systemctl start prometheus
      msg_ok "Updated Prometheus"
    fi
  else
    msg_warn "Prometheus not installed, skipping update"
  fi

  # --- Grafana ---
  if dpkg -s grafana >/dev/null 2>&1; then
    if [[ -f /etc/apt/sources.list.d/grafana.list ]] || [[ ! -f /etc/apt/sources.list.d/grafana.sources ]]; then
      setup_deb822_repo \
        "grafana" \
        "https://apt.grafana.com/gpg.key" \
        "https://apt.grafana.com" \
        "stable" \
        "main"
    fi
    msg_info "Updating Grafana"
    $STD apt update
    $STD apt --only-upgrade install -y grafana
    msg_ok "Updated Grafana"
  else
    msg_warn "Grafana not installed, skipping update"
  fi

  # --- Prometheus PVE Exporter ---
  if [[ -f /etc/systemd/system/prometheus-pve-exporter.service ]]; then
    msg_info "Stopping Service"
    systemctl stop prometheus-pve-exporter
    msg_ok "Stopped Service"

    export PVE_VENV_PATH="/opt/prometheus-pve-exporter/.venv"
    export PVE_EXPORTER_BIN="${PVE_VENV_PATH}/bin/pve_exporter"

    if [[ ! -d "$PVE_VENV_PATH" || ! -x "$PVE_EXPORTER_BIN" ]]; then
      PYTHON_VERSION="3.12" setup_uv
      msg_info "Migrating to uv/venv"
      rm -rf "$PVE_VENV_PATH"
      mkdir -p /opt/prometheus-pve-exporter
      cd /opt/prometheus-pve-exporter
      $STD uv venv --clear "$PVE_VENV_PATH"
      $STD "$PVE_VENV_PATH/bin/python" -m ensurepip --upgrade
      $STD "$PVE_VENV_PATH/bin/python" -m pip install --upgrade pip
      $STD "$PVE_VENV_PATH/bin/python" -m pip install prometheus-pve-exporter
      msg_ok "Migrated to uv/venv"
    else
      msg_info "Updating Prometheus PVE Exporter"
      PYTHON_VERSION="3.12" setup_uv
      $STD "$PVE_VENV_PATH/bin/python" -m pip install --upgrade prometheus-pve-exporter
      msg_ok "Updated Prometheus PVE Exporter"
    fi

    local service_file="/etc/systemd/system/prometheus-pve-exporter.service"
    if ! grep -q "${PVE_VENV_PATH}/bin/pve_exporter" "$service_file"; then
      msg_info "Updating systemd service"
      cat <<EOF >"$service_file"
[Unit]
Description=Prometheus Proxmox VE Exporter
Documentation=https://github.com/znerol/prometheus-pve-exporter
After=syslog.target network.target

[Service]
User=root
Restart=always
Type=simple
ExecStart=${PVE_VENV_PATH}/bin/pve_exporter \\
    --config.file=/opt/prometheus-pve-exporter/pve.yml \\
    --web.listen-address=0.0.0.0:9221
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
      $STD systemctl daemon-reload
      msg_ok "Updated systemd service"
    fi

    msg_info "Starting Service"
    systemctl start prometheus-pve-exporter
    msg_ok "Started Service"
  else
    msg_warn "Prometheus PVE Exporter not installed, skipping update"
  fi

  msg_ok "Updated successfully!"
  exit 0
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access the services using the following URLs:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}       ${YW}(Grafana)${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:9090${CL}     ${YW}(Prometheus)${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:9221${CL}     ${YW}(PVE Exporter)${CL}"

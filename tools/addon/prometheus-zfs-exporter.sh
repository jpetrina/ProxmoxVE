#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jakov Petrina (jpetrina)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/pdf/zfs_exporter

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/tools.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/error_handler.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func) 2>/dev/null || true
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "prometheus-zfs-exporter" "addon"

# Enable error handling
set -Eeuo pipefail
trap 'error_handler' ERR
load_functions

# ==============================================================================
# CONFIGURATION
# ==============================================================================
VERBOSE=${var_verbose:-no}
APP="prometheus-zfs-exporter"
APP_TYPE="tools"
BINARY_PATH="/usr/bin/zfs_exporter"
SERVICE_PATH="/etc/systemd/system/zfs_exporter.service"
REPO="pdf/zfs_exporter"

# ==============================================================================
# OS DETECTION
# ==============================================================================
if ! grep -qE 'ID=debian|ID=ubuntu' /etc/os-release 2>/dev/null; then
  echo -e "${CROSS} Unsupported OS detected. This script only supports Debian and Ubuntu."
  exit 238
fi

# ==============================================================================
# UNINSTALL
# ==============================================================================
function uninstall() {
  msg_info "Uninstalling Prometheus-ZFS-Exporter"
  systemctl disable -q --now zfs_exporter 2>/dev/null || true

  rm -f "$SERVICE_PATH"
  rm -f /usr/local/bin/update_prometheus-zfs-exporter
  rm -f "$BINARY_PATH"
  msg_ok "Prometheus-ZFS-Exporter has been uninstalled"
}

# ==============================================================================
# UPDATE
# ==============================================================================
function update() {
  fetch_and_deploy_gh_release "zfs_exporter" "$REPO" "prebuild" "latest" "/usr/bin" "zfs_exporter-*.linux-amd64.tar.gz"
  systemctl restart zfs_exporter
  msg_ok "Updated successfully!"
}

# ==============================================================================
# INSTALL
# ==============================================================================
function install() {
  fetch_and_deploy_gh_release "zfs_exporter" "$REPO" "prebuild" "latest" "/usr/bin" "zfs_exporter-*.linux-amd64.tar.gz"

  # ponytail: using upstream systemd unit, no custom config needed for this exporter
  msg_info "Creating service"
  cat <<EOF >"$SERVICE_PATH"
[Unit]
Description=zfs_exporter service
After=network-online.target

[Service]
Type=simple
ExecStart=$BINARY_PATH
User=root
Group=root
SyslogIdentifier=zfs_exporter
Restart=on-failure
RestartSec=100ms

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable -q --now zfs_exporter
  msg_ok "Created and started service"

  # Create update script
  msg_info "Creating update script"
  ensure_usr_local_bin_persist
  cat <<'UPDATEEOF' >/usr/local/bin/update_prometheus-zfs-exporter
#!/usr/bin/env bash
# prometheus-zfs-exporter Update Script
type=update bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/addon/prometheus-zfs-exporter.sh)"
UPDATEEOF
  chmod +x /usr/local/bin/update_prometheus-zfs-exporter
  msg_ok "Created update script (/usr/local/bin/update_prometheus-zfs-exporter)"

  echo ""
  msg_ok "Prometheus-ZFS-Exporter installed successfully"
  msg_ok "Metrics: ${BL}http://${LOCAL_IP}:9315/metrics${CL}"
  msg_ok "Service: ${BL}zfs_exporter${CL}"
}

# ==============================================================================
# MAIN
# ==============================================================================
header_info
ensure_usr_local_bin_persist
get_lxc_ip

# Handle type=update (called from update script)
if [[ "${type:-}" == "update" ]]; then
  if [[ -f "$BINARY_PATH" ]]; then
    update
  else
    msg_error "Prometheus-ZFS-Exporter is not installed. Nothing to update."
    exit 233
  fi
  exit 0
fi

# Check if already installed
if [[ -f "$BINARY_PATH" ]]; then
  msg_warn "Prometheus-ZFS-Exporter is already installed."
  echo ""

  echo -n "${TAB}Uninstall Prometheus-ZFS-Exporter? (y/N): "
  read -r uninstall_prompt
  if [[ "${uninstall_prompt,,}" =~ ^(y|yes)$ ]]; then
    uninstall
    exit 0
  fi

  echo -n "${TAB}Update Prometheus-ZFS-Exporter? (y/N): "
  read -r update_prompt
  if [[ "${update_prompt,,}" =~ ^(y|yes)$ ]]; then
    update
    exit 0
  fi

  msg_warn "No action selected. Exiting."
  exit 0
fi

# Fresh installation
msg_warn "Prometheus-ZFS-Exporter is not installed."
echo ""
echo -e "${TAB}${INFO} This will install:"
echo -e "${TAB}  - zfs_exporter (from GitHub release)"
echo -e "${TAB}  - Systemd service"
echo ""

echo -n "${TAB}Install Prometheus-ZFS-Exporter? (y/N): "
read -r install_prompt
if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  install
else
  msg_warn "Installation cancelled. Exiting."
  exit 0
fi

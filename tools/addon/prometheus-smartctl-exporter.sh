#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jakov Petrina (jpetrina)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/prometheus-community/smartctl_exporter

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/tools.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/error_handler.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func) 2>/dev/null || true
declare -f init_tool_telemetry &>/dev/null && init_tool_telemetry "prometheus-smartctl-exporter" "addon"

# Enable error handling
set -Eeuo pipefail
trap 'error_handler' ERR
load_functions

# ==============================================================================
# CONFIGURATION
# ==============================================================================
VERBOSE=${var_verbose:-no}
APP="prometheus-smartctl-exporter"
APP_TYPE="tools"
BINARY_PATH="/usr/bin/smartctl_exporter"
SERVICE_PATH="/etc/systemd/system/smartctl_exporter.service"
REPO="prometheus-community/smartctl_exporter"

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
  msg_info "Uninstalling Prometheus-SmartCTL-Exporter"
  systemctl disable -q --now smartctl_exporter 2>/dev/null || true

  rm -f "$SERVICE_PATH"
  rm -f /usr/local/bin/update_prometheus-smartctl-exporter
  rm -f "$BINARY_PATH"
  msg_ok "Prometheus-SmartCTL-Exporter has been uninstalled"
}

# ==============================================================================
# BUILD FROM SOURCE (latest release is too old)
# ==============================================================================
function build_from_source() {
  local target_dir="${1:-/tmp/smartctl_exporter-build}"

  msg_info "Building smartctl_exporter from source (latest release is outdated)"
  rm -rf "$target_dir"
  git clone --depth 1 https://github.com/$REPO "$target_dir"

  setup_go
  (
    cd "$target_dir"
    go mod tidy
    CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o smartctl_exporter . || {
      echo "Go build failed." >&2
      exit 1
    }
  ) || {
    msg_error "Build failed. Check /tmp/build-*.log for details."
    exit 1
  }

  /usr/bin/install -m 0755 "$target_dir/smartctl_exporter" "$BINARY_PATH"
  rm -rf "$target_dir"
  msg_ok "Built and installed smartctl_exporter from source"
}

# ==============================================================================
# UPDATE
# ==============================================================================
function update() {
  build_from_source
  systemctl restart smartctl_exporter
  msg_ok "Updated successfully!"
}

# ==============================================================================
# INSTALL
# ==============================================================================
function install() {
  build_from_source

  # ponytail: using upstream systemd unit, no custom config needed for this exporter
  msg_info "Creating service"
  cat <<EOF >"$SERVICE_PATH"
[Unit]
Description=smartctl_exporter service
After=network-online.target

[Service]
Type=simple
ExecStart=$BINARY_PATH
User=root
Group=root
SyslogIdentifier=smartctl_exporter
Restart=on-failure
RestartSec=100ms

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable -q --now smartctl_exporter
  msg_ok "Created and started service"

  # Create update script
  msg_info "Creating update script"
  ensure_usr_local_bin_persist
  cat <<'UPDATEEOF' >/usr/local/bin/update_prometheus-smartctl-exporter
#!/usr/bin/env bash
# prometheus-smartctl-exporter Update Script
type=update bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/addon/prometheus-smartctl-exporter.sh)"
UPDATEEOF
  chmod +x /usr/local/bin/update_prometheus-smartctl-exporter
  msg_ok "Created update script (/usr/local/bin/update_prometheus-smartctl-exporter)"

  echo ""
  msg_ok "Prometheus-SmartCTL-Exporter installed successfully"
  msg_ok "Metrics: ${BL}http://${LOCAL_IP}:9633/metrics${CL}"
  msg_ok "Service: ${BL}smartctl_exporter${CL}"
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
    msg_error "Prometheus-SmartCTL-Exporter is not installed. Nothing to update."
    exit 233
  fi
  exit 0
fi

# Check if already installed
if [[ -f "$BINARY_PATH" ]]; then
  msg_warn "Prometheus-SmartCTL-Exporter is already installed."
  echo ""

  echo -n "${TAB}Uninstall Prometheus-SmartCTL-Exporter? (y/N): "
  read -r uninstall_prompt
  if [[ "${uninstall_prompt,,}" =~ ^(y|yes)$ ]]; then
    uninstall
    exit 0
  fi

  echo -n "${TAB}Update Prometheus-SmartCTL-Exporter? (y/N): "
  read -r update_prompt
  if [[ "${update_prompt,,}" =~ ^(y|yes)$ ]]; then
    update
    exit 0
  fi

  msg_warn "No action selected. Exiting."
  exit 0
fi

# Fresh installation
msg_warn "Prometheus-SmartCTL-Exporter is not installed."
echo ""
echo -e "${TAB}${INFO} This will install:"
echo -e "${TAB}  - smartctl_exporter (built from source — latest release is outdated)"
echo -e "${TAB}  - Systemd service"
echo ""

echo -n "${TAB}Install Prometheus-SmartCTL-Exporter? (y/N): "
read -r install_prompt
if [[ "${install_prompt,,}" =~ ^(y|yes)$ ]]; then
  install
else
  msg_warn "Installation cancelled. Exiting."
  exit 0
fi

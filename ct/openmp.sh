#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://open.mp/docs/server/LinuxServerInstallation

APP="OpenMP Server"
var_tags="${var_tags:-game;voice}"
var_cpu="${var_cpu:-1}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
if [[ -z "${var_os:-}" ]] && command -v pveversion >/dev/null 2>&1; then
  var_os=$(msg_menu "Choose the container OS" \
    "debian" "Debian 13" \
    "alpine" "Alpine (smaller footprint)")
fi

if [[ "${var_os:-}" == "alpine" ]]; then
  var_ram="${var_ram:-512}"
  var_disk="${var_disk:-4}"
  var_version="${var_version:-3.24}"
else
  var_ram="${var_ram:-512}"
  var_disk="${var_disk:-4}"
  var_version="${var_version:-13}"
fi

header_info "$APP"
variables
color
catch_errors

# Fetch latest version from GitHub releases
get_latest_omp_version() {
  curl -fsSL https://api.github.com/repos/openmultiplayer/open.mp/releases/latest | grep -oP '"tag_name":\s*"v\K[0-9.]+'
}

update_deb_based() {
  if [[ ! -d /opt/omp-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(get_latest_omp_version)
  CURRENT_VERSION=$(cat ~/.openmp-version 2>/dev/null)

  if [[ "${RELEASE}" != "${CURRENT_VERSION}" ]] || [[ -z "${CURRENT_VERSION}" ]]; then
    msg_info "Stopping Service"
    systemctl stop openmp-server
    msg_ok "Stopped Service"

    msg_info "Updating OpenMP Server"
    cd /tmp
    curl -fsSL "https://github.com/openmultiplayer/open.mp/releases/download/v${RELEASE}/open.mp-linux-x86.tar.gz" -o openmp.tar.gz
    tar -xzf openmp.tar.gz
    cp -ru open.mp/* /opt/omp-server/
    rm -rf open.mp openmp.tar.gz
    echo "${RELEASE}" > ~/.openmp-version
    msg_ok "Updated OpenMP Server"

    msg_info "Starting Service"
    systemctl start openmp-server
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "Already up to date (v${RELEASE})"
  fi
}

update_alpine() {
  if [[ ! -d /opt/omp-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(get_latest_omp_version)
  CURRENT_VERSION=$(cat ~/.openmp-version 2>/dev/null)

  if [ "${RELEASE}" != "${CURRENT_VERSION}" ] || [ -z "${CURRENT_VERSION}" ]; then
    msg_info "Updating ${APP} LXC"
    $STD apk -U upgrade
    $STD service openmp-server stop
    cd /tmp
    curl -fsSL "https://github.com/openmultiplayer/open.mp/releases/download/v${RELEASE}/open.mp-linux-x86.tar.gz" -o openmp.tar.gz
    tar -xzf openmp.tar.gz
    cp -ru open.mp/* /opt/omp-server/
    rm -rf open.mp openmp.tar.gz
    echo "${RELEASE}" > ~/.openmp-version
    $STD service openmp-server start
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  run_os_update
}

start() {
  msg_info "Installing ${APP} dependencies"

  if [[ "${var_os:-}" == "alpine" ]]; then
    $STD apk add -U curl tar procps openrc
  else
    $STD dpkg --add-architecture i386
    $STD apt-get update
    $STD apt-get install -y screen curl tar libc6:i386 libatomic1 libatomic1:i386
  fi

  msg_ok "Installed ${APP} dependencies"
}

build_container() {
  # Create service account
  msg_info "Creating service account"
  if ! getent passwd svc-omp-server >/dev/null 2>&1; then
    useradd -M svc-omp-server
  fi
  usermod -L svc-omp-server
  usermod -aG svc-omp-server "$USER"
  msg_ok "Created service account"

  # Create server directory
  msg_info "Creating server directory"
  mkdir -p /opt/omp-server
  chown svc-omp-server:svc-omp-server /opt/omp-server
  chmod g+rwx /opt/omp-server
  chmod g+s /opt/omp-server
  chmod o-rwx /opt/omp-server
  msg_ok "Created server directory"

  # Download and extract latest release
  RELEASE=$(get_latest_omp_version)
  CURRENT_VERSION=$(cat ~/.openmp-version 2>/dev/null)

  if [[ "${RELEASE}" != "${CURRENT_VERSION}" ]] || [[ -z "${CURRENT_VERSION}" ]]; then
    msg_info "Downloading OpenMP Server v${RELEASE}"
    cd /tmp
    curl -fsSL "https://github.com/openmultiplayer/open.mp/releases/download/v${RELEASE}/open.mp-linux-x86.tar.gz" -o openmp.tar.gz
    tar -xzf openmp.tar.gz
    cp -ru open.mp/* /opt/omp-server/
    rm -rf open.mp openmp.tar.gz
    echo "${RELEASE}" > ~/.openmp-version
    msg_ok "Downloaded OpenMP Server v${RELEASE}"

    # Make server executable
    chmod +x /opt/omp-server/Server/omp-server
  else
    msg_ok "OpenMP Server v${RELEASE} already installed"
  fi

  # Create systemd service file (Debian-based only)
  if [[ "${var_os:-}" != "alpine" ]]; then
    cat > /etc/systemd/system/openmp-server.service << 'EOF'
[Unit]
Description=OpenMP Server
After=network.target

[Service]
Type=simple
User=svc-omp-server
WorkingDirectory=/opt/omp-server/Server
ExecStart=/opt/omp-server/Server/omp-server
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable openmp-server
  fi

  # Start the server
  msg_info "Starting OpenMP Server"
  if [[ "${var_os:-}" == "alpine" ]]; then
    if ! command -v rc-service >/dev/null 2>&1; then
      apk add --no-cache openrc
    fi
    cat > /etc/init.d/openmp-server << 'EOF'
#!/sbin/openrc-run
name="openmp-server"
description="OpenMP Server"
start() {
    su -s /bin/sh svc-omp-server -c "/opt/omp-server/Server/omp-server"
}
stop() {
    pkill -f omp-server
}
EOF
    chmod +x /etc/init.d/openmp-server
    rc-update add openmp-server default
  fi
  msg_ok "Started OpenMP Server"
}

build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}${IP}:7777${CL}"

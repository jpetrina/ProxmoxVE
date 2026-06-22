#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<<$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func)

function header_info {
  clear
  cat <<"EOF"
 ______               ____ _____ ____ 
 / ____/_______  ___  / __ ) ___// __ \
 / /_  / ___/ _ \/ _ \/ __  \__ \/ / / /
 / __/ / /  /  __/  __/ /_/ /__/ / /_/ / 
/_/   /_/   \___/\___/_____/____/_____/

EOF
}
header_info
echo -e "Loading..."
#API VARIABLES
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="freebsd-vm"
var_os="freebsd"
var_version="14.2"
#
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
HA=$(echo "\033[1;34m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
set -Eeo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP
function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  post_update_to_api "failed" "$exit_code"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
  cleanup_vmid
}

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1))
      continue
    fi
    if lvs --noheadings -o lv_name | grep -qE "(^|[-_])${try_id}($|[-_])"; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

function cleanup_vmid() {
  if qm status $VMID &>/dev/null; then
    qm stop $VMID &>/dev/null
    qm destroy $VMID &>/dev/null
  fi
}

function cleanup() {
  local exit_code=$?
  popd >/dev/null
  if [[ "${POST_TO_API_DONE:-}" == "true" && "${POST_UPDATE_DONE:-}" != "true" ]]; then
    if [[ $exit_code -eq 0 ]]; then
      post_update_to_api "done" "none"
    else
      post_update_to_api "failed" "$exit_code"
    fi
  fi
  rm -rf $TEMP_DIR
}

function check_disk_space() {
  local path="$1"
  local required_gb="$2"
  local available_kb=$(df -k "$path" | awk 'NR==2 {print $4}')
  local available_gb=$((available_kb / 1024 / 1024))
  if [ $available_gb -lt $required_gb ]; then
    return 1
  fi
  return 0
}

# Use disk-backed temp directory to avoid tmpfs/RAM size limits in /tmp
if [ -z "$TEMP_DIR" ]; then
  if [ -d "/var/tmp" ] && check_disk_space "/var/tmp" 20; then
    TEMP_DIR=$(mktemp -d /var/tmp/freebsd-vm.XXXXXX)
  elif [ -d "/tmp" ] && check_disk_space "/tmp" 20; then
    TEMP_DIR=$(mktemp -d)
  else
    # Fallback: try /var/tmp anyway, disk space check will catch it later
    TEMP_DIR=$(mktemp -d /var/tmp/freebsd-vm.XXXXXX)
  fi
fi
pushd $TEMP_DIR >/dev/null

if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "FreeBSD VM" --yesno "This will create a New FreeBSD VM. Proceed?" 10 58); then
  :
else
  header_info && echo -e "⚠ User exited script \n" && exit
fi

function msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

# This function checks the version of Proxmox Virtual Environment (PVE) and exits if the version is not supported.
# Supported: Proxmox VE 8.0.x – 8.9.x, 9.0 and 9.2
pve_check() {
  local PVE_VER
  PVE_VER="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"

  # Check for Proxmox VE 8.x: allow 8.0–8.9
  if [[ "$PVE_VER" =~ ^8\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 9)); then
      msg_error "This version of Proxmox VE is not supported."
      msg_error "Supported: Proxmox VE version 8.0 – 8.9"
      exit 105
    fi
    return 0
  fi

  # Check for Proxmox VE 9.x: allow 9.0 and 9.2
  if [[ "$PVE_VER" =~ ^9\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 2)); then
      msg_error "This version of Proxmox VE is not supported."
      msg_error "Supported: Proxmox VE version 9.0 – 9.2"
      exit 105
    fi
    return 0
  fi

  # All other unsupported versions
  msg_error "This version of Proxmox VE is not supported."
  msg_error "Supported versions: Proxmox VE 8.0 – 8.x or 9.0 – 9.2"
  exit 105
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo -e "\n ${CROSS} This script will not work with PiMox! \n"
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function ssh_check() {
  if command -v pveversion >/dev/null 2>&1; then
    if [ -n "${SSH_CLIENT:+x}" ]; then
      if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
        echo "you've been warned"
      else
        clear
        exit
      fi
    fi
  fi
}

function exit-script() {
  clear
  echo -e "⚠  User exited script \n"
  exit
}

function get_available_bridges() {
  ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}' | sort
}

function default_settings() {
  VMID=$(get_valid_nextid)
  FORMAT=",efitype=4m"
  MACHINE=""
  DISK_CACHE=""
  HN="freebsd"
  CPU_TYPE=""
  CORE_COUNT="4"
  RAM_SIZE="8192"
  BRG="vmbr0"
  IP_ADDR=""
  LAN_GW=""
  NETMASK=""
  VLAN=""
  MAC=$GEN_MAC
  MTU=""
  START_VM="yes"
  METHOD="default"

  # Detect available bridges
  local AVAILABLE_BRIDGES
  AVAILABLE_BRIDGES=$(get_available_bridges)
  local BRIDGE_COUNT
  BRIDGE_COUNT=$(echo "$AVAILABLE_BRIDGES" | wc -l)

  echo -e "${DGN}Using Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${DGN}Using Hostname: ${BGN}${HN}${CL}"
  echo -e "${DGN}Allocated Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${DGN}Allocated RAM: ${BGN}${RAM_SIZE}${CL}"
  if ! ip link show "${BRG}" &>/dev/null; then
    msg_error "Bridge '${BRG}' does not exist"
    exit
  else
    echo -e "${DGN}Using Bridge: ${BGN}${BRG}${CL}"
  fi
  echo -e "${DGN}Using VLAN: ${BGN}Default${CL}"
  echo -e "${DGN}Using MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${DGN}Using Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${BL}Creating a FreeBSD VM using the above default settings${CL}"
}

function advanced_settings() {
  local ip_regex='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'
  METHOD="advanced"
  [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)
  while true; do
    if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 $VMID --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VMID" ]; then
        VMID=$(get_valid_nextid)
      fi
      if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
        echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"
        sleep 2
        continue
      fi
      echo -e "${DGN}Virtual Machine ID: ${BGN}$VMID${CL}"
      break
    else
      exit-script
    fi
  done

  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 \
    "i440fx" "Machine i440fx" ON \
    "q35" "Machine q35" OFF \
    3>&1 1>&2 2>&3); then
    if [ $MACH = q35 ]; then
      echo -e "${DGN}Using Machine Type: ${BGN}$MACH${CL}"
      FORMAT=""
      MACHINE=" -machine q35"
    else
      echo -e "${DGN}Using Machine Type: ${BGN}$MACH${CL}"
      FORMAT=",efitype=4m"
      MACHINE=""
    fi
  else
    exit-script
  fi

  if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "KVM64 (Default)" ON \
    "1" "Host" OFF \
    3>&1 1>&2 2>&3); then
    if [ $CPU_TYPE1 = "1" ]; then
      echo -e "${DGN}Using CPU Model: ${BGN}Host${CL}"
      CPU_TYPE=" -cpu host"
    else
      echo -e "${DGN}Using CPU Model: ${BGN}KVM64${CL}"
      CPU_TYPE=""
    fi
  else
    exit-script
  fi

  if DISK_CACHE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DISK CACHE" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "None (Default)" ON \
    "1" "Write Through" OFF \
    3>&1 1>&2 2>&3); then
    if [ $DISK_CACHE = "1" ]; then
      echo -e "${DGN}Using Disk Cache: ${BGN}Write Through${CL}"
      DISK_CACHE="cache=writethrough,"
    else
      echo -e "${DGN}Using Disk Cache: ${BGN}None${CL}"
      DISK_CACHE=""
    fi
  else
    exit-script
  fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 FreeBSD --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$VM_NAME" ]; then
      HN="FreeBSD"
    else
      HN=$(echo "${VM_NAME,,}" | tr -cs 'a-z0-9-' '-' | sed 's/^-//;s/-$//')
      if [ "$HN" != "${VM_NAME,,}" ]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "HOSTNAME ADJUSTED" --msgbox "Invalid characters detected. Hostname has been adjusted to:\n\n  $HN" 10 58
      fi
    fi
    echo -e "${DGN}Using Hostname: ${BGN}$HN${CL}"
  else
    exit-script
  fi

  while true; do
    if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 4 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$CORE_COUNT" ]; then CORE_COUNT="4"; fi
      if [[ "$CORE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${DGN}Allocated Cores: ${BGN}$CORE_COUNT${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "CPU Cores must be a positive integer (e.g., 4)." 8 58
    else
      exit-script
    fi
  done

  while true; do
    if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 8192 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$RAM_SIZE" ]; then RAM_SIZE="8192"; fi
      if [[ "$RAM_SIZE" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${DGN}Allocated RAM: ${BGN}$RAM_SIZE${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "RAM Size must be a positive integer in MiB (e.g., 8192)." 8 58
    else
      exit-script
    fi
  done

  if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $BRG ]; then
      BRG="vmbr0"
    fi
    if ! ip link show "${BRG}" &>/dev/null; then
      msg_error "Bridge '${BRG}' does not exist"
      exit
    fi
    echo -e "${DGN}Using Bridge: ${BGN}$BRG${CL}"
  else
    exit-script
  fi

  if IP_ADDR=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set an IP address (leave empty for DHCP)" 8 58 $IP_ADDR --title "IP ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $IP_ADDR ]; then
      echo -e "${DGN}Using DHCP${CL}"
    else
      if [[ -n "$IP_ADDR" && ! "$IP_ADDR" =~ $ip_regex ]]; then
        msg_error "Invalid IP Address format. Needs to be 0.0.0.0, was $IP_ADDR"
        exit
      fi
      echo -e "${DGN}Using IP ADDRESS: ${BGN}$IP_ADDR${CL}"
      if LAN_GW=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Gateway IP" 8 58 $LAN_GW --title "GATEWAY IP ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z $LAN_GW ]; then
          echo -e "${DGN}Gateway needs to be set if ip is not dhcp${CL}"
          exit-script
        fi
        if [[ -n "$LAN_GW" && ! "$LAN_GW" =~ $ip_regex ]]; then
          msg_error "Invalid IP Address format for Gateway. Needs to be 0.0.0.0, was $LAN_GW"
          exit
        fi
        echo -e "${DGN}Using GATEWAY ADDRESS: ${BGN}$LAN_GW${CL}"
      fi
      if NETMASK=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a netmask (24 for example)" 8 58 $NETMASK --title "NETMASK" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z $NETMASK ]; then
          echo -e "${DGN}Netmask needs to be set if ip is not dhcp${CL}"
        fi
        if [[ -n "$NETMASK" && ! ("$NETMASK" =~ ^[0-9]+$ && "$NETMASK" -ge 1 && "$NETMASK" -le 32) ]]; then
          msg_error "Invalid NETMASK format. Needs to be 1-32, was $NETMASK"
          exit
        fi
        echo -e "${DGN}Using NETMASK: ${BGN}$NETMASK${CL}"
      else
        exit-script
      fi
    fi
  else
    exit-script
  fi

  if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 $GEN_MAC --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MAC1 ]; then
      MAC="$GEN_MAC"
    else
      MAC="$MAC1"
    fi
    echo -e "${DGN}Using MAC Address: ${BGN}$MAC${CL}"
  else
    exit-script
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create FreeBSD VM?" --no-button Do-Over 10 58); then
    echo -e "${RD}Creating a FreeBSD VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58); then
    header_info
    echo -e "${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

arch_check
pve_check
ssh_check
start_script
post_to_api_vm

msg_info "Validating Storage"
while read -r line; do
  TAG=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{printf "%-10s", $2}')
  FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')
VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  msg_error "Unable to detect a valid storage location."
  exit
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."
msg_info "Retrieving the URL for the FreeBSD qcow2 disk image"
# Use latest stable FreeBSD amd64 qcow2 VM image (generic, not UFS/ZFS)
RELEASE_LIST="$(curl -s https://download.freebsd.org/releases/VM-IMAGES/ |
  grep -Eo '[0-9]+\.[0-9]+-RELEASE' |
  sort -Vr |
  uniq)"
URL=""
FREEBSD_VER=""
for ver in $RELEASE_LIST; do
  candidate="https://download.freebsd.org/releases/VM-IMAGES/${ver}/amd64/Latest/FreeBSD-${ver}-amd64.qcow2.xz"
  if curl -fsI "$candidate" >/dev/null 2>&1; then
    FREEBSD_VER="$ver"
    URL="$candidate"
    break
  fi
done
if [ -z "$URL" ]; then
  msg_error "Could not find generic FreeBSD amd64 qcow2 image (non-UFS/ZFS)."
  exit 115
fi
msg_ok "Download URL: ${CL}${BL}${URL}${CL}"

# Check available disk space (require at least 20GB for safety)
if ! check_disk_space "$TEMP_DIR" 20; then
  AVAILABLE_GB=$(df -h "$TEMP_DIR" | awk 'NR==2 {print $4}')
  msg_error "Insufficient disk space in temporary directory ($TEMP_DIR)."
  msg_error "Available: ${AVAILABLE_GB}, Required: ~20GB for FreeBSD image decompression."
  msg_error "Please free up space or ensure /tmp has sufficient storage."
  exit 214
fi

msg_info "Downloading FreeBSD Image"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
msg_ok "Downloaded ${CL}${BL}$(basename "$URL")${CL}"

# Check disk space again before decompression
if ! check_disk_space "$TEMP_DIR" 15; then
  AVAILABLE_GB=$(df -h "$TEMP_DIR" | awk 'NR==2 {print $4}')
  msg_error "Insufficient disk space for decompression."
  msg_error "Available: ${AVAILABLE_GB}, Required: ~15GB for decompressed image."
  exit 214
fi

msg_info "Decompressing FreeBSD Image (this may take a few minutes)"
FILE=FreeBSD.qcow2
if ! unxz -cv $(basename $URL) >${FILE}; then
  msg_error "Failed to decompress FreeBSD image."
  msg_error "This is usually caused by insufficient disk space."
  df -h "$TEMP_DIR"
  exit 115
fi

# Remove the compressed file to save space
rm -f "$(basename "$URL")"
msg_ok "Decompressed ${CL}${BL}${FILE}${CL}"

STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format qcow2"
  THIN=""
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
*)
  DISK_EXT=""
  DISK_REF=""
  DISK_IMPORT="-format raw"
  ;;
esac
for i in {0,1}; do
  disk="DISK$i"
  eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done

msg_info "Creating a FreeBSD VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci

# Retry pvesm alloc on transient zfs_request "got timeout" errors (#14127)
alloc_attempt=1
alloc_max=4
alloc_delay=5
while :; do
  alloc_err=$(pvesm alloc $STORAGE $VMID $DISK0 4M 2>&1 >/dev/null) && break
  if [[ "$alloc_err" == *"got timeout"* && $alloc_attempt -lt $alloc_max ]]; then
    echo -e "${YW}[WARN]${CL} pvesm alloc hit zfs timeout (attempt $alloc_attempt/$alloc_max), retrying in ${alloc_delay}s..."
    pvesm free "${DISK0_REF}" &>/dev/null || true
    sleep "$alloc_delay"
    alloc_attempt=$((alloc_attempt + 1))
    alloc_delay=$((alloc_delay * 2))
    continue
  fi
  echo -e "$alloc_err" >&2
  exit 220
done
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} &>/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=2G \
  -boot order=scsi0 \
  -serial0 socket \
  -tags community-script >/dev/null
qm resize $VMID scsi0 20G >/dev/null
DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://community-scripts.org' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>FreeBSD VM</h2>

  <p style='margin: 16px 0;'>
    <a href='https://ko-fi.com/community_scripts' target='_blank' rel='noopener noreferrer'>
      <img src='https://img.shields.io/badge/&#x2615;-Buy us a coffee-blue' alt='spend Coffee' />
    </a>
  </p>

  <span style='margin: 0 10px;'>
    <i class="fa fa-github fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>GitHub</a>
  </span>
  <span style='margin: 0 10px;'>
    <i class="fa fa-comments fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE/discussions' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Discussions</a>
  </span>
  <span style='margin: 0 10px;'>
    <i class="fa fa-exclamation-circle fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE/issues' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Issues</a>
  </span>
</div>
EOF
)
qm set $VMID -description "$DESCRIPTION" >/dev/null

msg_info "Bridge interfaces are being added."
qm set $VMID \
  -net0 virtio,bridge=${BRG},macaddr=${MAC}${VLAN}${MTU} 2>/dev/null
msg_ok "Bridge interfaces have been successfully added."

msg_ok "Created a FreeBSD VM ${CL}${BL}(${HN})"
msg_info "Starting FreeBSD VM"
qm start $VMID
sleep 5

msg_ok "Started FreeBSD VM"

msg_ok "Completed successfully!\n"
if [ "$IP_ADDR" != "" ]; then
  echo -e "${INFO}${YW} Access it using the following IP:${CL}"
  echo -e "${TAB}${BGN}${IP_ADDR}${CL}"
else
  echo -e "${INFO}${YW} IP was set to DHCP.${CL}"
  echo -e "${INFO}${BGN}To find the IP login to the VM shell${CL}"
fi

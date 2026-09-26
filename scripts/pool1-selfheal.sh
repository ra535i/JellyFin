#!/usr/bin/env bash
# pool1-selfheal.sh — bounded, read-only-first RAID/USB recovery
#
# Install this file root:root 0755 at /usr/local/sbin/pool1-selfheal.
# It never creates, zeros, adds, removes, or rebuilds RAID members.
set -Eeuo pipefail

POOL=/var/mnt/pool1
MD=/dev/md0
ARRAY_UUID=cd644f30:f6b25111:17ea4808:21d6ee81
USB_SERIAL=20170331000DA
STATE_DIR=/var/lib/pool1-selfheal
EXPECTED_EVENTS=
EXPECTED_UPDATE=

LOCK=/run/lock/pool1-selfheal.lock

DISKS=(
  /dev/disk/by-id/usb-External_USB3.0_DISK00_20170331000DA-0:0
  /dev/disk/by-id/usb-External_USB3.0_DISK01_20170331000DA-0:1
  /dev/disk/by-id/usb-External_USB3.0_DISK02_20170331000DA-0:2
  /dev/disk/by-id/usb-External_USB3.0_DISK03_20170331000DA-0:3
  /dev/disk/by-id/usb-External_USB3.0_DISK04_20170331000DA-0:4
)

log() {
  local msg=$1
  printf '%s\n' "$msg"
  logger -t pool1-selfheal -- "$msg" 2>/dev/null || true
}

fail() {
  log "FAIL: $1"
  exit 1
}

require_root() {
  [[ $EUID -eq 0 ]] || fail 'must run as root'
}

member_check() {
  local disk=$1 expected_role=$2 data uuid events update role
  [[ -e $disk ]] || return 1
  data=$(mdadm --examine --export "$disk" 2>/dev/null) || return 1
  grep -qx "MD_LEVEL=raid5" <<<"$data" || return 1
  grep -qx "MD_DEVICES=5" <<<"$data" || return 1
  grep -qx "MD_UUID=$ARRAY_UUID" <<<"$data" || return 1
  uuid=$(awk -F= '$1=="MD_DEV_UUID"{print $2}' <<<"$data")
  [[ -n $uuid ]] || return 1
  events=$(awk -F= '$1=="MD_EVENTS"{print $2}' <<<"$data")
  [[ -n $events ]] || return 1
  if [[ -n $EXPECTED_EVENTS && $events != "$EXPECTED_EVENTS" ]]; then
    return 1
  fi
  EXPECTED_EVENTS=${EXPECTED_EVENTS:-$events}
  update=$(awk -F= '$1=="MD_UPDATE_TIME"{print $2}' <<<"$data")
  [[ -n $update ]] || return 1
  if [[ -n $EXPECTED_UPDATE && $update != "$EXPECTED_UPDATE" ]]; then
    return 1
  fi
  EXPECTED_UPDATE=${EXPECTED_UPDATE:-$update}
  role=$(mdadm --examine "$disk" 2>/dev/null | sed -n 's/^[[:space:]]*Device Role[[:space:]]*:[[:space:]]*Active device \([0-9][0-9]*\).*/\1/p')
  [[ $role == "$expected_role" ]] || return 1
  mdadm --examine "$disk" 2>/dev/null | grep -qE '^[[:space:]]+State[[:space:]]*:[[:space:]]+clean$' || return 1
  mdadm --examine "$disk" 2>/dev/null | grep -qE 'Array State[[:space:]]*:[[:space:]]*AAAAA' || return 1
  mdadm --examine "$disk" 2>/dev/null | grep -qE 'Checksum[[:space:]]*:[[:space:]].* - correct' || return 1
}

all_members_ready() {
  local disk i
  EXPECTED_EVENTS=
  EXPECTED_UPDATE=
  [[ ${#DISKS[@]} -eq 5 ]] || return 1
  for i in "${!DISKS[@]}"; do
    disk=${DISKS[$i]}
    member_check "$disk" "$i" || return 1
  done
}

md_healthy() {
  [[ -b $MD ]] || return 1
  grep -qE '^md0 : active ' /proc/mdstat || return 1
  grep -qE '\[5/5\] \[UUUUU\]' /proc/mdstat || return 1
  mountpoint -q "$POOL" || return 1
  findmnt -no OPTIONS "$POOL" | grep -qw rw
}

status() {
  printf '=== pool1 self-heal status ===\n'
  printf 'USB: '
  local serial_path
  serial_path=$(grep -l -x "$USB_SERIAL" /sys/bus/usb/devices/*/serial 2>/dev/null | head -1 || true)
  if [[ -n $serial_path ]]; then
    printf 'present at %s\n' "${serial_path%/serial}"
  else
    printf 'not enumerated\n'
  fi
  printf '%s\n' '--- mdstat ---'
  cat /proc/mdstat
  printf '%s\n' '--- mount ---'
  findmnt -T "$POOL" -o TARGET,SOURCE,FSTYPE,OPTIONS 2>&1 || true
  printf '%s\n' '--- members ---'
  local disk i
  for i in "${!DISKS[@]}"; do
    disk=${DISKS[$i]}
    if member_check "$disk" "$i"; then
      printf 'OK   %s\n' "$disk"
    else
      printf 'BAD  %s\n' "$disk"
    fi
  done
}

stop_pool_writers() {
  # These are the only media writers. Jellyfin is stopped too so its container
  # cannot retain a bind mount while mdadm is being replaced.
  systemctl stop jellyfin.service jellyseerr.service bazarr.service \
    radarr.service sabnzbd.service sonarr.service 2>/dev/null || true

  if [[ -S /run/user/1000/bus ]]; then
    runuser -u skim -- env XDG_RUNTIME_DIR=/run/user/1000 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
      systemctl --user stop fileflows.service qbittorrent.service 2>/dev/null || true
  fi
  runuser -u skim -- env XDG_RUNTIME_DIR=/run/user/1000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    podman stop fileflows qbittorrent 2>/dev/null || true
}

start_pool_services() {
  systemctl start mdmonitor.service 2>/dev/null || true
  systemctl start jellyfin.service jellyseerr.service bazarr.service \
    radarr.service sabnzbd.service sonarr.service

  if [[ -S /run/user/1000/bus ]]; then
    runuser -u skim -- env XDG_RUNTIME_DIR=/run/user/1000 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
      systemctl --user unmask --runtime qbittorrent.service 2>/dev/null || true
    runuser -u skim -- env XDG_RUNTIME_DIR=/run/user/1000 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
      systemctl --user start fileflows.service qbittorrent.service
  fi
}

recover_full() {
  mkdir -p "$STATE_DIR"
  exec 9>"$LOCK"
  flock -n 9 || fail 'another recovery is already running'

  if md_healthy; then
    log 'OK: md0 is complete and pool1 is mounted read-write; no action needed'
    return 0
  fi

  log 'Pool is unavailable or read-only; validating USB members before full restoration'
  if ! all_members_ready; then
    log 'USB members are incomplete or not ready; resetting the enclosure bridge'
    /usr/sbin/usbreset "SN:$USB_SERIAL" 2>&1 || true
    udevadm settle --timeout=20 || true
  fi
  all_members_ready || fail 'did not find five matching clean RAID members'

  stop_pool_writers
  mountpoint -q "$POOL" && umount "$POOL"

  if [[ -b $MD ]]; then
    if findmnt -rn -S "$MD" >/dev/null 2>&1; then
      fail "$MD is still mounted"
    fi
    if find /sys/block/md0/holders -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
      fail "$MD still has a kernel holder"
    fi
    if fuser -s "$MD" 2>/dev/null; then
      fail "$MD still has an open user"
    fi
    mdadm --stop "$MD" 2>/dev/null || mdadm --stop --force "$MD"
  fi

  mdadm --assemble "$MD" "${DISKS[@]}"
  mount "$MD" "$POOL"
  findmnt -no OPTIONS "$POOL" | grep -qw rw || fail 'pool did not mount read-write'

  local sample
  sample=$(find "$POOL" -xdev -type f -size +1M -print -quit 2>/dev/null || true)
  [[ -n $sample ]] || fail 'pool mounted but no media sample was found'
  dd if="$sample" of=/dev/null bs=1M count=1 iflag=direct status=none

  start_pool_services
  log 'RECOVERED: md0 assembled read-write as [UUUUU]; pool read test passed; media stack started'
}

main() {
  case "${1:---status}" in
    --status)
      require_root
      status
      ;;
    --recover-rw)
      require_root
      recover_full
      ;;
    *)
      printf 'usage: %s --status|--recover-rw\n' "$0" >&2
      exit 2
      ;;
  esac
}

main "$@"

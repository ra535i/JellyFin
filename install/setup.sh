#!/bin/bash
# suvannmedia master installer
# Run as root: sudo bash install/setup.sh
#
# Requires the production single-volume media filesystem mounted at
# /var/mnt/pool1. Application state stays on the internal NVMe.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MEDIA_ROOT=/var/mnt/pool1
CONFIG_ROOT=/home/skim/jellyfin-configs

user_systemctl() {
    runuser -u skim -- env \
      XDG_RUNTIME_DIR=/run/user/1000 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
      systemctl --user "$@"
}

printf '%s\n' '════════════════════════════════════════════'
printf '%s\n' '  SUVANNMEDIA STACK SETUP'
printf '%s\n' '════════════════════════════════════════════'

mountpoint -q "$MEDIA_ROOT" || {
    echo "ERROR: $MEDIA_ROOT is not mounted; refusing to start services against an empty path." >&2
    exit 1
}

mkdir -p "$CONFIG_ROOT"
chown -R skim:skim "$CONFIG_ROOT"
chmod 711 /home/skim
if command -v semanage &>/dev/null; then
    semanage fcontext -a -t container_file_t \
      '/var/home/skim/jellyfin-configs(/.*)?' 2>/dev/null || \
    semanage fcontext -m -t container_file_t \
      '/var/home/skim/jellyfin-configs(/.*)?'
    restorecon -RF /var/home/skim/jellyfin-configs
fi
install -d -o skim -g skim -m 0775 "$CONFIG_ROOT/fileflows/runner-temp"

if ! podman image exists localhost/fileflows-amd-vaapi:latest; then
    echo 'ERROR: localhost/fileflows-amd-vaapi:latest is missing. Build it using README.md before setup.' >&2
    exit 1
fi

bash "$REPO/install/install_jellyfin.sh"
bash "$REPO/install/install_arr_stack.sh"

printf '%s\n' '═══ HTTP VERIFY ═══'
declare -A PORT=(
  [jellyfin]=8096 [jellyseerr]=5055 [sabnzbd]=8085 [prowlarr]=9696
  [radarr]=7878 [sonarr]=8989 [bazarr]=6767 [cleanuparr]=11011 [flaresolverr]=8191 [fileflows]=5000
)
for svc in jellyfin jellyseerr sabnzbd prowlarr radarr sonarr bazarr cleanuparr flaresolverr fileflows; do
    code=$(curl --max-time 8 -sS -o /dev/null -w '%{http_code}' \
      "http://127.0.0.1:${PORT[$svc]}/" 2>/dev/null || true)
    printf '  %-12s HTTP %s\n' "$svc" "${code:-000}"
done
printf '  %-12s %s\n' 'fileflows-unit:' "$(user_systemctl is-active fileflows || true)"

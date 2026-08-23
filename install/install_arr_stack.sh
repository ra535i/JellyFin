#!/bin/bash
# media-server stack installer
# RUN AS ROOT: sudo bash install/install_arr_stack.sh
#
# Installs the Arr services as root systemd-managed podman containers and
# FileFlows as the skim user service. App state lives on local NVMe.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SYSTEMD_DIR="$REPO/systemd"
CONFIG_ROOT=/home/skim/jellyfin-configs
SYSTEM_SERVICES=(sabnzbd prowlarr radarr sonarr bazarr jellyseerr)

user_systemctl() {
    runuser -u skim -- env \
      XDG_RUNTIME_DIR=/run/user/1000 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
      systemctl --user "$@"
}

# --- Preflight -------------------------------------------------------------
echo "═══ PREFLIGHT ═══"
mountpoint -q /mnt/media || {
    echo "ERROR: /mnt/media is not mounted. Start mergerfs first." >&2
    exit 1
}

for d in /mnt/media/downloads /mnt/media/movies /mnt/media/tv \
         /mnt/media/fileflows-working \
         "$CONFIG_ROOT/sabnzbd" "$CONFIG_ROOT/prowlarr" \
         "$CONFIG_ROOT/radarr" "$CONFIG_ROOT/sonarr" \
         "$CONFIG_ROOT/bazarr" "$CONFIG_ROOT/jellyseerr" \
         "$CONFIG_ROOT/fileflows/Data" "$CONFIG_ROOT/fileflows/logs" \
         "$CONFIG_ROOT/fileflows/temp"; do
    mkdir -p "$d"
done
chown -R 1000:1000 "$CONFIG_ROOT"
chmod 711 /home/skim
if command -v semanage &>/dev/null; then
    semanage fcontext -a -t container_file_t \
      '/var/home/skim/jellyfin-configs(/.*)?' 2>/dev/null || \
    semanage fcontext -m -t container_file_t \
      '/var/home/skim/jellyfin-configs(/.*)?'
    restorecon -RF /var/home/skim/jellyfin-configs
fi
echo "dirs and SELinux labels ok"

# --- Install system units --------------------------------------------------
echo; echo "═══ INSTALLING SYSTEM UNITS ═══"
for svc in "${SYSTEM_SERVICES[@]}"; do
    cp "$SYSTEMD_DIR/$svc.service" /etc/systemd/system/
done
systemctl daemon-reload

for svc in "${SYSTEM_SERVICES[@]}"; do
    systemctl enable "$svc" >/dev/null
    systemctl restart "$svc"
done

# --- Install FileFlows as the only enabled user unit -----------------------
echo; echo "═══ INSTALLING FILEFLOWS USER UNIT ═══"
systemctl disable --now fileflows.service 2>/dev/null || true
install -d -o skim -g skim /home/skim/.config/systemd/user
ln -sfn "$SYSTEMD_DIR/fileflows.service" \
  /home/skim/.config/systemd/user/fileflows.service
chown -h skim:skim /home/skim/.config/systemd/user/fileflows.service
loginctl enable-linger skim
user_systemctl daemon-reload
user_systemctl enable fileflows >/dev/null
user_systemctl restart fileflows

# --- Verify ----------------------------------------------------------------
echo; echo "═══ STATUS ═══"
for svc in "${SYSTEM_SERVICES[@]}"; do
    printf "%-14s active=%-8s enabled=%s\n" "$svc" \
      "$(systemctl is-active "$svc")" "$(systemctl is-enabled "$svc")"
done
printf "%-14s active=%-8s enabled=%s\n" fileflows \
  "$(user_systemctl is-active fileflows)" \
  "$(user_systemctl is-enabled fileflows)"

echo; echo "═══ HTTP CHECK ═══"
declare -A PORT=(
  [sabnzbd]=8085 [prowlarr]=9696 [radarr]=7878 [sonarr]=8989
  [bazarr]=6767 [jellyseerr]=5055 [fileflows]=5000
)
for svc in "${SYSTEM_SERVICES[@]}" fileflows; do
    port="${PORT[$svc]}"
    code=$(curl --max-time 8 -sS -o /dev/null -w "%{http_code}" \
      "http://127.0.0.1:$port/" 2>/dev/null || true)
    printf "  %-12s HTTP %s\n" "$svc" "${code:-000}"
done

echo; echo "Done. Complete first-run app setup and wiring as documented in README.md."

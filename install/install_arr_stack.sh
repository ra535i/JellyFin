#!/bin/bash
# media-server stack installer
# RUN AS ROOT:  sudo bash install/install_arr_stack.sh
#
# Installs the full Arr stack as systemd-managed podman containers:
#   SABnzbd, Prowlarr, Radarr, Sonarr, Bazarr, Jellyseerr
# (Jellyfin is installed separately by install/install_jellyfin.sh)
#
# Idempotent: safe to re-run. Survives reboots (all units enabled).

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SYSTEMD_DIR="$REPO/systemd"

SERVICES=(sabnzbd prowlarr radarr sonarr bazarr jellyseerr)

# --- Preflight: mount points & images -------------------------------------
echo "═══ PREFLIGHT ═══"
for d in /mnt/media/downloads /mnt/media/movies /mnt/media/tv \
         /mnt/jellyfin/config/sabnzbd /mnt/jellyfin/config/prowlarr \
         /mnt/jellyfin/config/radarr /mnt/jellyfin/config/sonarr \
         /mnt/jellyfin/config/bazarr /mnt/jellyfin/config/jellyseerr; do
    mkdir -p "$d"
done
echo "dirs ok"

# --- Install systemd units -------------------------------------------------
echo; echo "═══ INSTALLING SYSTEMD UNITS ═══"
for svc in "${SERVICES[@]}"; do
    cp "$SYSTEMD_DIR/$svc.service" /etc/systemd/system/
done
systemctl daemon-reload
echo "units installed"

# --- Enable + start --------------------------------------------------------
echo; echo "═══ ENABLING (boot survival) ═══"
for svc in "${SERVICES[@]}"; do
    systemctl enable "$svc" >/dev/null 2>&1 && echo "enabled: $svc" || echo "enable-fail: $svc"
done

echo; echo "═══ STARTING ═══"
for svc in "${SERVICES[@]}"; do
    systemctl restart "$svc" && echo "started: $svc" || echo "start-fail: $svc"
done

# --- Verify ----------------------------------------------------------------
echo; echo "═══ STATUS ═══"
for svc in "${SERVICES[@]}"; do
    state=$(systemctl is-active "$svc")
    enabled=$(systemctl is-enabled "$svc")
    printf "%-14s active=%-8s enabled=%s\n" "$svc" "$state" "$enabled"
done

echo; echo "═══ HTTP CHECK ═══"
declare -A PORT=( [sabnzbd]=8085 [prowlarr]=9696 [radarr]=7878 [sonarr]=8989 [bazarr]=6767 [jellyseerr]=5055 )
for svc in "${SERVICES[@]}"; do
    port="${PORT[$svc]}"
    code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$port/" 2>/dev/null || echo "000")
    echo "  $svc -> http://127.0.0.1:$port  (HTTP $code)"
done

echo; echo "═══ DON'T FORGET ═══"
echo "After first boot of each UI, complete setup, then wire them together:"
echo "  Prowlarr -> add indexer(s) + Radarr/Sonarr as apps"
echo "  SABnzbd  -> add usenet provider + enable API"
echo "  Radarr   -> add SABnzbd download client + Prowlarr indexers, set root folder /movies"
echo "  Sonarr   -> add SABnzbd download client + Prowlarr indexers, set root folder /tv"
echo "  Jellyseerr -> connect Jellyfin + Radarr + Sonarr"
echo "Done."

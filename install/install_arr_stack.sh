#!/bin/bash
# media-server stack installer
# RUN AS ROOT:  sudo bash install/install_arr_stack.sh
#
# Installs the full Arr stack as systemd-managed podman containers:
#   SABnzbd, Prowlarr, Radarr, Sonarr, Bazarr, Jellyseerr, FileFlows
# (Jellyfin is installed separately by install/install_jellyfin.sh)
#
# Idempotent: safe to re-run. Survives reboots (all units enabled).

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SYSTEMD_DIR="$REPO/systemd"

SERVICES=(sabnzbd prowlarr radarr sonarr bazarr jellyseerr fileflows)

# --- Preflight: mount points & images -------------------------------------
echo "═══ PREFLIGHT ═══"

# Verify jellyfin drive mount
if ! mountpoint -q /var/mnt/jellyfin && ! mountpoint -q /mnt/jellyfin; then
    echo "ERROR: /var/mnt/jellyfin not mounted. Run install/setup.sh first to mount the config drive." >&2
    exit 1
fi
for d in /mnt/media/downloads /mnt/media/movies /mnt/media/tv /mnt/media/fileflows-working \
         /mnt/jellyfin/config/sabnzbd /mnt/jellyfin/config/prowlarr \
         /mnt/jellyfin/config/radarr /mnt/jellyfin/config/sonarr \
         /mnt/jellyfin/config/bazarr /mnt/jellyfin/config/jellyseerr \
         /mnt/jellyfin/config/fileflows /mnt/jellyfin/config/fileflows/logs \
         /mnt/jellyfin/config/fileflows/temp; do
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
declare -A PORT=( [sabnzbd]=8085 [prowlarr]=9696 [radarr]=7878 [sonarr]=8989 [bazarr]=6767 [jellyseerr]=5055 [fileflows]=5000 )
for svc in "${SERVICES[@]}"; do
    port="${PORT[$svc]}"
    code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$port/" 2>/dev/null || echo "000")
    echo "  $svc -> http://127.0.0.1:$port  (HTTP $code)"
done

# --- Import FileFlows flows ------------------------------------------------
echo; echo "═══ FILEFLOWS: IMPORTING FLOWS ═══"
FLOW_DIR="$REPO/fileflows/flows"
IMPORT_SCRIPT="$REPO/fileflows/import_flows.sh"
if [ -d "$FLOW_DIR" ] && ls "$FLOW_DIR"/*.json &>/dev/null; then
    podman cp "$FLOW_DIR" fileflows:/tmp/flows
    podman cp "$IMPORT_SCRIPT" fileflows:/tmp/import_flows.sh
    if podman exec fileflows bash /tmp/import_flows.sh; then
        echo "  flows imported"
    else
        echo "  WARN: flow import had errors (FileFlows may not be ready)"
    fi
else
    echo "  (no flow files at $FLOW_DIR — skipping)"
fi

echo; echo "═══ DON'T FORGET ═══"
echo "After first boot of each UI, complete setup, then wire them together:"
echo "  Prowlarr -> add indexer(s) + Radarr/Sonarr as apps"
echo "  SABnzbd  -> add usenet provider + enable API"
echo "  Radarr   -> add SABnzbd download client + Prowlarr indexers, set root folder /movies"
echo "  Sonarr   -> add SABnzbd download client + Prowlarr indexers, set root folder /tv"
echo "  Jellyseerr -> connect Jellyfin + Radarr + Sonarr"
echo "Done."
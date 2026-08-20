#!/bin/bash
# media-server - MASTER SETUP
# RUN AS ROOT:  sudo bash install/setup.sh
#
# Full setup from a fresh-ish state:
#   1. Mount the jellyfin config drive (var-mnt-jellyfin.mount)
#   2. Install mergerfs (pool the USB media drives)
#   3. Install Jellyfin
#   4. Install the Arr stack (SABnzbd, Prowlarr, Radarr, Sonarr, Bazarr, Jellyseerr, FileFlows)
#   5. Build the custom FileFlows image with ffmpeg + VAAPI
#
# Idempotent — safe to re-run any time.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

echo "════════════════════════════════════════════"
echo "  MEDIA SERVER MASTER SETUP"
echo "════════════════════════════════════════════"

# 0. Mount jellyfin config drive
echo; echo "═══ 0. CONFIG DRIVE ═══"
if ! mountpoint -q /var/mnt/jellyfin; then
    if [ -f /etc/systemd/system/var-mnt-jellyfin.mount ]; then
        systemctl enable var-mnt-jellyfin.mount
        systemctl start var-mnt-jellyfin.mount
        echo "var-mnt-jellyfin.mount enabled + started"
    else
        echo "ERROR: var-mnt-jellyfin.mount not found at /etc/systemd/system/"
        echo "Install it: cp systemd/var-mnt-jellyfin.mount /etc/systemd/system/ && systemctl daemon-reload"
        exit 1
    fi
else
    echo "Config drive already mounted"
fi

if ! mountpoint -q /mnt/media; then
    echo "WARN: /mnt/media not mounted yet. mergerfs install will handle this."
fi

# 1. Ensure mergerfs binary + service
echo; echo "═══ 1. MERGERFS ═══"
bash "$REPO/install/install_mergerfs.sh"
echo "mergerfs done"

# 2. Build custom FileFlows image
echo; echo "═══ 2. BUILD FILEFLOWS IMAGE ═══"
if ! podman image exists localhost/fileflows-amd-vaapi:latest; then
    podman run -d --name ff-builder docker.io/revenz/fileflows:latest
    sleep 5
    podman exec -u 0 ff-builder apt update
    podman exec -u 0 ff-builder apt install -y ffmpeg vainfo mesa-va-drivers intel-media-va-driver-non-free
    podman commit ff-builder localhost/fileflows-amd-vaapi:latest
    podman rm -f ff-builder
    echo "Custom FileFlows image built"
else
    echo "FileFlows image already exists"
fi

# 3. Jellyfin
echo; echo "═══ 3. JELLYFIN ═══"
bash "$REPO/install/install_jellyfin.sh"

# 4. Arr stack
echo; echo "═══ 4. ARR STACK ═══"
bash "$REPO/install/install_arr_stack.sh"

# 5. Verify all
echo; echo "═══ VERIFY ═══"
for svc in var-mnt-jellyfin.mount mergerfs jellyfin sabnzbd prowlarr radarr sonarr bazarr jellyseerr fileflows; do
    state=$(systemctl is-active "$svc" 2>/dev/null || echo "dead")
    printf "  %-20s %s\n" "$svc:" "$state"
done

echo; echo "════════════════════════════════════════════"
echo "  SETUP COMPLETE"
echo "════════════════════════════════════════════"
echo "  Jellyfin   : http://$(hostname -I | awk '{print $1}'):8096"
echo "  SABnzbd    : http://$(hostname -I | awk '{print $1}'):8085"
echo "  Prowlarr   : http://$(hostname -I | awk '{print $1}'):9696"
echo "  Radarr     : http://$(hostname -I | awk '{print $1}'):7878"
echo "  Sonarr     : http://$(hostname -I | awk '{print $1}'):8989"
echo "  Bazarr     : http://$(hostname -I | awk '{print $1}'):6767"
echo "  Jellyseerr : http://$(hostname -I | awk '{print $1}'):5055"
echo "  FileFlows  : http://$(hostname -I | awk '{print $1}'):5000"
echo
echo "  NEXT: wire apps together (see README 'Wiring the apps together'),"
echo "  then deploy Cloudflare Tunnel: bash cloudflare/install_tunnel.sh"
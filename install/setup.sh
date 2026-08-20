#!/bin/bash
# media-server - MASTER SETUP
# RUN AS ROOT:  sudo bash install/setup.sh
#
# Full setup from a fresh-ish state:
#   1. Install mergerfs (binary already staged at /usr/local/bin)
#   2. Ensure drives are mounted (fstab)
#   3. Install Jellyfin
#   4. Install the Arr stack (SABnzbd, Prowlarr, Radarr, Sonarr, Bazarr, Jellyseerr)
#
# Idempotent — safe to re-run any time.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

echo "════════════════════════════════════════════"
echo "  MEDIA SERVER MASTER SETUP"
echo "════════════════════════════════════════════"

# 0. Preflight: mounts must be present
echo; echo "═══ 0. CHECKING MOUNTS ═══"
df -h /mnt/media | tail -1
if ! mountpoint -q /mnt/media; then
    echo "ERROR: /mnt/media not mounted. Mount the drives first (see README). Aborting." >&2
    exit 1
fi

# 1. Ensure mergerfs binary + service
echo; echo "═══ 1. MERGERFS ═══"
if [ ! -x /usr/local/bin/mergerfs ] && [ -x /usr/local/sbin/mount.mergerfs ]; then
    echo "mergerfs binary present"
else
    echo "MERGE: mergerfs binary expected at /usr/local/bin/mergerfs"
fi
if [ -f /etc/systemd/system/mergerfs.service ]; then
    systemctl enable mergerfs.service
    systemctl restart mergerfs.service
    echo "mergerfs service ok"
else
    echo "WARN: mergerfs.service not found - see mergerfs install notes"
fi

# 2. Jellyfin
echo; echo "═══ 2. JELLYFIN ═══"
bash "$REPO/install/install_jellyfin.sh"

# 3. Arr stack
echo; echo "═══ 3. ARR STACK ═══"
bash "$REPO/install/install_arr_stack.sh"

echo; echo "════════════════════════════════════════════"
echo "  SETUP COMPLETE"
echo "════════════════════════════════════════════"
echo "  Jellyfin   : http://192.168.50.152:8096"
echo "  SABnzbd    : http://192.168.50.152:8085"
echo "  Prowlarr   : http://192.168.50.152:9696"
echo "  Radarr     : http://192.168.50.152:7878"
echo "  Sonarr     : http://192.168.50.152:8989"
echo "  Bazarr     : http://192.168.50.152:6767"
echo "  Jellyseerr : http://192.168.50.152:5055"
echo "  FileFlows  : http://192.168.50.152:5000"
echo
echo "  NEXT: add usenet provider + indexer creds (see README section 'Usenet accounts')"

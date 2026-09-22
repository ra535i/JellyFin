#!/bin/bash
# Jellyfin systemd service installer
# RUN AS ROOT:  sudo bash install/install_jellyfin.sh
# Installs Jellyfin as a systemd-managed podman container.
# Requires: /var/mnt/pool1 (single ext4 media filesystem); app state lives on local NVMe.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MEDIA_ROOT=/var/mnt/pool1

echo "═══ JELLYFIN INSTALL ═══"

mountpoint -q "$MEDIA_ROOT" || {
    echo "ERROR: $MEDIA_ROOT is not mounted; refusing to create media directories." >&2
    exit 1
}
mkdir -p "$MEDIA_ROOT/movies" "$MEDIA_ROOT/tv" "$MEDIA_ROOT/music"

# Config/data/cache dirs on local NVMe
CONFIG_ROOT=/home/skim/jellyfin-configs
mkdir -p "$CONFIG_ROOT/config" "$CONFIG_ROOT/data" \
         "$CONFIG_ROOT/cache" "$CONFIG_ROOT/data/transcodes"
chown -R 1000:1000 "$CONFIG_ROOT"

# SELinux fix (if needed)
if command -v semanage &>/dev/null; then
    chmod 711 /home/skim
    semanage fcontext -a -t container_file_t \
      '/var/home/skim/jellyfin-configs(/.*)?' 2>/dev/null || \
    semanage fcontext -m -t container_file_t \
      '/var/home/skim/jellyfin-configs(/.*)?'
    restorecon -RF /var/home/skim/jellyfin-configs
fi

# Copy systemd unit
cp "$REPO/systemd/jellyfin.service" /etc/systemd/system/jellyfin.service
systemctl daemon-reload

# Remove old quadlet if present
rm -f /etc/containers/systemd/jellyfin.container

# Enable + start
systemctl enable jellyfin.service
systemctl restart jellyfin.service

# Verify
sleep 5
echo "  enabled: $(systemctl is-enabled jellyfin)"
echo "  active:  $(systemctl is-active jellyfin)"
echo "  HTTP:    $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8096/ 2>/dev/null || echo 'down')"
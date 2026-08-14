#!/bin/bash
# Mergerfs install script
# RUN AS ROOT:  sudo bash install/install_mergerfs.sh
# Downloads the static mergerfs binary and installs the systemd service.
# No reboot required, no rpm-ostree layering.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

echo "═══ MERGERFS INSTALL ═══"

# --- Download static binary ---
TAG="2.42.0"
URL="https://github.com/trapexit/mergerfs/releases/download/${TAG}/mergerfs-${TAG}-static-linux_amd64.tar.gz"
TMP=$(mktemp -d)

echo "Downloading mergerfs ${TAG}..."
curl -sL --max-time 60 -o "$TMP/mergerfs.tar.gz" "$URL"
tar xzf "$TMP/mergerfs.tar.gz" -C "$TMP"

# --- Install binaries ---
install -m 755 "$TMP/usr/local/bin/mergerfs" /usr/local/bin/mergerfs
install -m 755 "$TMP/usr/local/bin/mergerfs-fusermount" /usr/local/bin/mergerfs-fusermount
install -m 755 "$TMP/sbin/mount.mergerfs" /usr/local/sbin/mount.mergerfs
mkdir -p /usr/local/lib/mergerfs
install -m 644 "$TMP/usr/local/lib/mergerfs/preload.so" /usr/local/lib/mergerfs/preload.so

rm -rf "$TMP"

# Verify
/usr/local/bin/mergerfs --version || { echo "ERROR: mergerfs binary failed"; exit 1; }

# --- Install systemd service ---
mkdir -p /mnt/media
cp "$REPO/systemd/mergerfs.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable mergerfs.service
systemctl restart mergerfs.service

echo "  enabled: $(systemctl is-enabled mergerfs)"
echo "  active:  $(systemctl is-active mergerfs)"
echo "  pool:    $(df -h /mnt/media | tail -1)"
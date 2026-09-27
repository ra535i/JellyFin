#!/bin/bash
# Mirror recoverable application state to Seth's OneDrive account.
# Credentials and databases are intentionally excluded from Git but retained here.
set -euo pipefail
shopt -s globstar nullglob

SOURCE=/home/skim/jellyfin-configs
DESTINATION='onedrive:Backups/SuvannMedia/config-current'
HISTORY_ROOT='onedrive:Backups/SuvannMedia/config-history'
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
STAGING=$(mktemp -d "$SOURCE/.backup-staging.XXXXXX")

cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT

command -v rclone >/dev/null || {
  echo 'ERROR: rclone is required for SuvannMedia configuration backup.' >&2
  exit 2
}
command -v sqlite3 >/dev/null || {
  echo 'ERROR: sqlite3 is required to make consistent live database snapshots.' >&2
  exit 2
}
for command in podman zstd; do
  command -v "$command" >/dev/null || {
    echo "ERROR: $command is required to preserve the FileFlows image." >&2
    exit 2
  }
done
test -d "$SOURCE" || {
  echo "ERROR: configuration root is missing: $SOURCE" >&2
  exit 2
}

# SQLite's online backup command creates a consistent copy while its application
# continues to run. Copying a live main database plus -wal/-shm sidecars is not
# restore-safe and caused the first backup attempt to fail.
databases=(
  "$SOURCE"/**/*.db
  "$SOURCE"/**/*.sqlite
  "$SOURCE"/**/*.sqlite3
)
for database in "${databases[@]}"; do
  relative=${database#"$SOURCE/"}
  snapshot="$STAGING/$relative"
  mkdir -p "$(dirname "$snapshot")"
  sqlite3 "$database" ".backup '$snapshot'"
done

# Some required host-level state intentionally lives outside CONFIG_ROOT. Save it
# beside the database snapshots so a replacement host retains the configured
# torrent fallback, Cloudflare tunnel identity, and exact rootless user units.
for source_path in \
  /home/skim/JellyFin/torrent/.env \
  /home/skim/.cloudflared/config.yml \
  /home/skim/.cloudflared/credentials.json \
  /home/skim/.config/systemd/user/gluetun.service \
  /home/skim/.config/systemd/user/qbittorrent.service; do
  if [ -f "$source_path" ]; then
    relative=${source_path#/home/skim/}
    destination="$STAGING/recovery-host/$relative"
    mkdir -p "$(dirname "$destination")"
    cp -a "$source_path" "$destination"
  fi
done

# The custom FileFlows image is built locally, so retain an immutable export by
# image digest. It is uploaded only once for a given image and can be loaded on
# a replacement host without relying on mutable package repositories.
IMAGE=localhost/fileflows-amd-vaapi:latest
IMAGE_DIGEST=$(podman image inspect "$IMAGE" --format '{{.Digest}}')
IMAGE_NAME="fileflows-amd-vaapi-${IMAGE_DIGEST#sha256:}.tar.zst"
IMAGE_REMOTE='onedrive:Backups/SuvannMedia/images'
if [ -z "$(rclone lsf "$IMAGE_REMOTE/$IMAGE_NAME" --files-only)" ]; then
  podman save "$IMAGE" | zstd -T0 -19 -o "$STAGING/$IMAGE_NAME"
  sha256sum "$STAGING/$IMAGE_NAME" > "$STAGING/$IMAGE_NAME.sha256"
  rclone copyto "$STAGING/$IMAGE_NAME" "$IMAGE_REMOTE/$IMAGE_NAME"
  rclone copyto "$STAGING/$IMAGE_NAME.sha256" "$IMAGE_REMOTE/$IMAGE_NAME.sha256"
  rm -f "$STAGING/$IMAGE_NAME" "$STAGING/$IMAGE_NAME.sha256"
fi

# FileFlows runner scratch, caches, logs, sockets, qBittorrent's recreated Nova
# search engines, and live SQLite files are rebuildable runtime state. Rootless
# user-namespace ownership can make the Nova files unreadable to the backup job.
# The database snapshots above replace every SQLite database in the OneDrive mirror.
rclone sync "$SOURCE/" "$DESTINATION/" \
  --backup-dir "$HISTORY_ROOT/$STAMP" \
  --exclude '/.backup-staging*/**' \
  --exclude '/recovery-host/**' \
  --exclude '/fileflows/runner-temp/**' \
  --exclude '/fileflows/logs/**' \
  --exclude '/fileflows/temp/**' \
  --exclude '/fileflows/Temp/**' \
  --exclude '/cache/**' \
  --exclude '/metadata/**' \
  --exclude '/log/**' \
  --exclude '**/logs/**' \
  --exclude '/qbittorrent/qBittorrent/nova3/engines/**' \
  --exclude '/qbittorrent/qBittorrent/BT_backup/**' \
  --exclude '**/ipc-socket' \
  --exclude '**/*.db' \
  --exclude '**/*.sqlite' \
  --exclude '**/*.sqlite3' \
  --exclude '**/*-wal' \
  --exclude '**/*-shm' \
  --create-empty-src-dirs \
  --retries 3 \
  --low-level-retries 10 \
  --stats 1m

# A prior interrupted run may have left stale WAL/SHM/socket files in the
# mirror. They must not accompany the fresh database snapshots during restore.
rclone delete "$DESTINATION/" \
  --include '**/*-wal' \
  --include '**/*-shm' \
  --include '**/ipc-socket'

rclone copy "$STAGING/" "$DESTINATION/" \
  --backup-dir "$HISTORY_ROOT/$STAMP" \
  --retries 3 \
  --low-level-retries 10 \
  --stats 1m

echo "SuvannMedia configuration backup complete: $DESTINATION (history: $HISTORY_ROOT/$STAMP)"

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

# FileFlows runner scratch, caches, logs, sockets, and live SQLite files are
# rebuildable runtime state. The database snapshots above replace every SQLite
# database in the OneDrive mirror.
rclone sync "$SOURCE/" "$DESTINATION/" \
  --backup-dir "$HISTORY_ROOT/$STAMP" \
  --exclude '/.backup-staging*/**' \
  --exclude '/fileflows/runner-temp/**' \
  --exclude '/fileflows/logs/**' \
  --exclude '/fileflows/temp/**' \
  --exclude '/fileflows/Temp/**' \
  --exclude '/cache/**' \
  --exclude '/metadata/**' \
  --exclude '/log/**' \
  --exclude '**/logs/**' \
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

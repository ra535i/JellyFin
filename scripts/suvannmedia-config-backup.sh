#!/bin/bash
# Mirror recoverable application state to Seth's OneDrive account.
# Credentials and databases are intentionally excluded from Git but retained here.
set -euo pipefail

SOURCE=/home/skim/jellyfin-configs
DESTINATION='onedrive:Backups/SuvannMedia/config-current'
HISTORY_ROOT='onedrive:Backups/SuvannMedia/config-history'
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

command -v rclone >/dev/null || {
  echo 'ERROR: rclone is required for SuvannMedia configuration backup.' >&2
  exit 2
}
test -d "$SOURCE" || {
  echo "ERROR: configuration root is missing: $SOURCE" >&2
  exit 2
}

# FileFlows runner data is disposable job scratch on the secondary NVMe. Runtime
# caches and logs are likewise rebuildable; all application databases/configuration
# and the FileFlows Data directory are included.
rclone sync "$SOURCE/" "$DESTINATION/" \
  --backup-dir "$HISTORY_ROOT/$STAMP" \
  --exclude '/fileflows/runner-temp/**' \
  --exclude '/fileflows/logs/**' \
  --exclude '/fileflows/temp/**' \
  --exclude '/fileflows/Temp/**' \
  --exclude '/cache/**' \
  --exclude '/metadata/**' \
  --exclude '/log/**' \
  --create-empty-src-dirs \
  --retries 3 \
  --low-level-retries 10 \
  --stats 1m

echo "SuvannMedia configuration backup complete: $DESTINATION (history: $HISTORY_ROOT/$STAMP)"

#!/bin/bash
# Produce a recoverable Hermes profile snapshot, including skills, plugins,
# memories, cron definitions, scripts, configuration, and SQLite state.
set -euo pipefail
umask 077

PROFILE=/home/skim/.hermes/profiles/last
HERMES_ROOT=/home/skim/.hermes
REMOTE='onedrive:Hermes/Backups'
WORK_ROOT="$PROFILE/backups"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$WORK_ROOT"
WORK=$(mktemp -d "$WORK_ROOT/hermes-backup-${STAMP}.XXXXXX")
ARCHIVE="$WORK_ROOT/hermes-profile-${STAMP}.tar.zst"
CHECKSUM="$ARCHIVE.sha256"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

for command in sqlite3 tar zstd sha256sum rclone; do
  command -v "$command" >/dev/null || {
    echo "ERROR: required command is unavailable: $command" >&2
    exit 2
  }
done

mkdir -p "$WORK/profile" "$WORK/recovery/host" "$WORK/recovery/systemd-user"

# Capture persistent profile material. Runtime caches, logs, old state snapshots,
# language-server caches, and installed binaries are reproducible and excluded.
for item in config.yaml .env auth.json SOUL.md memories skills plugins scripts sessions profiles workspace source-checks vault hooks platforms pairing google_token.json; do
  if [ -e "$PROFILE/$item" ]; then
    cp -a "$PROFILE/$item" "$WORK/profile/"
  fi
done

# The live gateway runs from the default Hermes home and routes into this
# profile. Preserve its host-level identity and default profile for a like-for-
# like replacement-host recovery.
for item in config.yaml .env auth.json vault hooks platforms pairing google_token.json sessions cron gateway_state.json; do
  if [ -e "$HERMES_ROOT/$item" ]; then
    cp -a "$HERMES_ROOT/$item" "$WORK/recovery/host/"
  fi
done
if [ -d "$WORK/recovery/host/cron/output" ]; then
  rm -rf "$WORK/recovery/host/cron/output"
fi
if [ -d "$HERMES_ROOT/profiles/default" ]; then
  mkdir -p "$WORK/recovery/host/profiles"
  cp -a "$HERMES_ROOT/profiles/default" "$WORK/recovery/host/profiles/"
fi
for database in state.db shared-state.db kanban.db projects.db verification_evidence.db; do
  if [ -f "$HERMES_ROOT/$database" ]; then
    sqlite3 "$HERMES_ROOT/$database" ".backup '$WORK/recovery/host/$database'"
  fi
done
for unit in hermes-gateway.service hermes-dashboard.service hermes-onedrive-backup.service hermes-onedrive-backup.timer; do
  if [ -f "/home/skim/.config/systemd/user/$unit" ]; then
    cp -a "/home/skim/.config/systemd/user/$unit" "$WORK/recovery/systemd-user/"
  fi
done
if [ -d "$PROFILE/cron" ]; then
  cp -a "$PROFILE/cron" "$WORK/profile/cron"
  rm -rf "$WORK/profile/cron/output"
fi

# SQLite's online backup API gives a coherent copy while Hermes remains online.
for database in state.db projects.db verification_evidence.db; do
  if [ -f "$PROFILE/$database" ]; then
    sqlite3 "$PROFILE/$database" ".backup '$WORK/profile/$database'"
  fi
done

# This contains the rclone remote definition needed to reach the OneDrive backup.
# It is inside the account-protected archive and must not be committed to Git.
if [ -f /home/skim/.config/rclone/rclone.conf ]; then
  cp -a /home/skim/.config/rclone/rclone.conf "$WORK/recovery/rclone.conf"
fi

printf 'created_utc=%s\nhermes_profile=%s\n' "$STAMP" "$PROFILE" > "$WORK/manifest.txt"
tar --zstd -cf "$ARCHIVE" -C "$WORK" profile recovery manifest.txt
sha256sum "$ARCHIVE" > "$CHECKSUM"
rclone copyto "$ARCHIVE" "$REMOTE/$(basename "$ARCHIVE")"
rclone copyto "$CHECKSUM" "$REMOTE/$(basename "$CHECKSUM")"
printf 'Hermes profile backup complete: %s/%s\n' "$REMOTE" "$(basename "$ARCHIVE")"
rm -f "$ARCHIVE" "$CHECKSUM"

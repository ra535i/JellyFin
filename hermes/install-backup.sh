#!/bin/bash
# Install the repository-managed Hermes backup job for user skim.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE=/home/skim/.hermes/profiles/last
USER_UNIT_DIR=/home/skim/.config/systemd/user

install -d -o skim -g skim -m 0700 "$PROFILE/scripts" "$PROFILE/backups" "$USER_UNIT_DIR"
install -o skim -g skim -m 0700 "$REPO/hermes/hermes-onedrive-backup.sh" \
  "$PROFILE/scripts/hermes-onedrive-backup.sh"
install -o skim -g skim -m 0644 "$REPO/hermes/hermes-onedrive-backup.service" \
  "$USER_UNIT_DIR/hermes-onedrive-backup.service"
install -o skim -g skim -m 0644 "$REPO/hermes/hermes-onedrive-backup.timer" \
  "$USER_UNIT_DIR/hermes-onedrive-backup.timer"

loginctl enable-linger skim
runuser -u skim -- env XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  systemctl --user daemon-reload
runuser -u skim -- env XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  systemctl --user enable hermes-onedrive-backup.timer

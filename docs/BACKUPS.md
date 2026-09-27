# Backup policy

The public `ra535i/JellyFin` repository holds reviewed, deployable source:
systemd units, installer scripts, flow definitions, operational scripts, and
recovery documentation. It **does not** hold application databases, API tokens,
VPN credentials, Cloudflare credentials, or backup archives.

## Scheduled jobs

`install/setup.sh` installs and enables these persistent systemd timers:

- `suvannmedia-config-backup.timer` — Sundays at approximately 02:00 local
  time. It mirrors recoverable application state from
  `/home/skim/jellyfin-configs` to
  `onedrive:Backups/SuvannMedia/config-current`, retaining remote replacements
  under `config-history/<UTC timestamp>/`.
- `suvannmedia-repo-backup.timer` — Sundays at approximately 03:00 local time.
  It fetches and pushes `main` only when the worktree is clean. It never makes
  an automatic commit: a dirty tree could contain a secret or runtime state and
  must be reviewed first.

The configuration backup excludes FileFlows `runner-temp`, app caches, metadata,
and logs because those are rebuildable runtime data. It includes FileFlows
`Data`, Arr databases/configuration, Jellyfin state, downloader configuration,
and other recoverable application state.

OneDrive access is authenticated through the host's `rclone` `onedrive` remote.
The data contains service credentials, so protect the Microsoft account with MFA
and do not share this backup path. If independent client-side encryption is
wanted later, migrate this destination to an `rclone crypt` remote and retain
its recovery configuration outside the backed-up machine.

## Hermes profile backup

The lingering user timer `hermes-onedrive-backup.timer` runs Sundays at
approximately 04:00 local time and writes a compressed recovery archive plus a
SHA-256 sidecar to `onedrive:Hermes/Backups/`. It includes the active `last`
profile's skills, plugins, memories, scripts, cron definitions, session index,
configuration, credentials, and coherent SQLite snapshots. Rebuildable logs,
caches, installed binaries, and stale state snapshots are excluded.

## Restore the Hermes profile

This restores the active `last` profile from an archive in
`onedrive:Hermes/Backups/`. The archive contains credentials and OAuth state;
use a private directory and do not commit or share its contents. Restore to a
staging directory first, verify the checksum, and preserve the current profile
for rollback rather than deleting it.

1. Install Hermes and `rclone` on the replacement host, then configure the
   `onedrive` remote with access to the backup account. List the available
   archives and choose the desired UTC timestamp:

   ```bash
   rclone lsl onedrive:Hermes/Backups
   ```

2. Download both the archive and its checksum into a private staging directory,
   then verify and inspect it. Substitute the selected archive name exactly:

   ```bash
   umask 077
   RECOVERY_DIR=$(mktemp -d)
   ARCHIVE=hermes-profile-YYYYMMDDTHHMMSSZ.tar.zst
   rclone copyto "onedrive:Hermes/Backups/$ARCHIVE" "$RECOVERY_DIR/$ARCHIVE"
   rclone copyto "onedrive:Hermes/Backups/$ARCHIVE.sha256" \
     "$RECOVERY_DIR/$ARCHIVE.sha256"
   cd "$RECOVERY_DIR"
   sha256sum -c "$ARCHIVE.sha256"
   tar --zstd -tf "$ARCHIVE" | less
   ```

   The checksum command must report `OK`. The archive should contain a top-level
   `profile/` directory and a `recovery/` directory. Stop here if either check
   fails; do not restore an unverified archive.

3. Extract to the staging directory, stop the profile's gateway so it cannot
   write state during replacement, and move the current profile aside. This
   retains a rollback copy at the timestamped path:

   ```bash
   tar --zstd -xf "$ARCHIVE"
   test -f "$RECOVERY_DIR/profile/config.yaml"

   systemctl --user stop hermes-gateway.service
   PROFILE_ROOT=/home/skim/.hermes/profiles
   BACKUP_NAME="last-pre-restore-$(date -u +%Y%m%dT%H%M%SZ)"
   mkdir -p "$PROFILE_ROOT"
   if [ -d "$PROFILE_ROOT/last" ]; then
     mv "$PROFILE_ROOT/last" "$PROFILE_ROOT/$BACKUP_NAME"
   fi
   mv "$RECOVERY_DIR/profile" "$PROFILE_ROOT/last"
   ```

4. Start Hermes and verify both the gateway and the restored profile. A successful
   gateway status plus a valid profile configuration confirms the base restore:

   ```bash
   systemctl --user start hermes-gateway.service
   systemctl --user is-active hermes-gateway.service
   test -f /home/skim/.hermes/profiles/last/config.yaml
   hermes -p last cron list
   ```

   Confirm the expected skills, memories, cron jobs, and messaging connection in
   Hermes before removing the rollback directory. If the restored gateway fails,
   stop it, move `last` aside, rename `$BACKUP_NAME` back to `last`, and start
   the gateway again.

The Hermes archive also includes `recovery/rclone.conf` so a recovered profile
retains the former rclone remote definition. Treat that file as a secret; copy
it only if needed and keep its permissions private.

## Manual verification

```bash
sudo systemctl start suvannmedia-config-backup.service
sudo systemctl status suvannmedia-config-backup.service --no-pager
rclone lsf -R onedrive:Backups/SuvannMedia/config-current

sudo systemctl start suvannmedia-repo-backup.service
sudo systemctl status suvannmedia-repo-backup.service --no-pager
```

## Restore outline

1. Stop only the affected applications before restoring their state. Preserve
   Jellyfin streaming whenever a targeted restore is sufficient.
2. Copy the needed path from `config-current` (or an appropriate dated history
   snapshot) back to `/home/skim/jellyfin-configs`.
3. Reapply ownership/SELinux labels, then start and HTTP-check the affected
   service.
4. Follow `docs/RECOVERY.md` for a full-host disaster recovery.

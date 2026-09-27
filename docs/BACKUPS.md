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

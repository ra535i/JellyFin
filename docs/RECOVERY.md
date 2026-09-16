# Disaster Recovery Guide

> **Purpose:** Rebuild the entire media server from scratch after catastrophic loss
> (server destroyed, drives failed, complete reinstall). Covers Bazzite/Fedora
> immutable Linux with systemd-managed podman containers.
>
> **Last verified:** Sep 2026

## Overview

The stack is designed for recovery — all containers are stateless (configs on NVMe,
media on USB array). A fresh Bazzite install plus this repo gets you operational
in under an hour, but **you must provide** several credentials and external
accounts (not stored in this repo).

### Recovery time estimate

| Step | Est. time | Who |
|------|-----------|-----|
| Fresh OS install | ~15 min | You |
| Clone repo + install dependencies | ~5 min | Automated |
| SELinux + config prep | ~2 min | Automated |
| Start containers | ~3 min | Automated |
| Restore configs from backup | ~10-30 min | Manual (file copy) |
| Recreate Cloudflare tunnel | ~5 min | You (provide token) |
| Wire apps together | ~15 min | Manual via web UI |
| **Total** | **~1 hour** | |

If **no config backup exists**, add ~1-2h for first-time setup of each app.

## Prerequisites — You Will Need

These are **not** in this repo. Gather them before starting:

### Credentials to provide

| Item | Where you get it | Notes |
|------|-----------------|-------|
| **Cloudflare API token** | Cloudflare Dashboard → My Profile → API Tokens | Needs `Cloudflare Tunnel` edit perms on suvannmedia.com |
| **PIA OpenVPN username** | Private Internet Access → Account page | Used by Gluetun tunnel |
| **PIA OpenVPN password** | Private Internet Access → Account page | |
| **SABnzbd API key** | `jellyfin-configs/sabnzbd/sabnzbd.ini` (from backup) | Or generate new one from SAB UI |
| **TMDb API key** | themoviedb.org → Settings → API | Free, used by FileFlows flow |
| **NZBGeek API key** | nzbgeek.info → Account | Prowlarr indexer |

### Subscriptions needed

| Service | Cost | Purpose |
|---------|------|---------|
| Cloudflare (domain registration) | $8-12/yr | suvannmedia.com |
| Frugal Usenet | ~$5/mo | Primary download source |
| Private Internet Access | ~$4/mo | Torrent fallback VPN |
| NZBGeek | ~$10/yr | Indexer |
| TMDb | Free | Movie metadata |

## Recovery Steps

### Phase 0: OS Install

```bash
# Install Bazzite (or Fedora Atomic) from USB
# https://bazzite.gg — download the ISO

# After first boot, update everything
rpm-ostree update
sudo systemctl reboot

# Enable SSH for remote work
sudo systemctl enable --now sshd
```

### Phase 1: Clone Repo + Prep System

```bash
# 1. Clone this repo
sudo dnf install -y git podman
git clone https://github.com/ra535i/JellyFin.git /opt/jellyfin
cd /opt/jellyfin

# 2. Create config directory with proper SELinux labels
mkdir -p /home/skim/jellyfin-configs
sudo chmod 711 /home/skim
sudo semanage fcontext -a -t container_file_t \
  '/var/home/skim/jellyfin-configs(/.*)?'
sudo restorecon -RF /var/home/skim/jellyfin-configs

# 3. (If pooling) Install mergerfs — skip for single-volume setups
#    Current production uses a single 5.5T USB RAID5 volume.
#    See systemd/mergerfs.service if you need to rebuild a pool.
# sudo bash install/install_mergerfs.sh

# 4. Build custom FileFlows image (needs ffmpeg + VAAPI)
podman run -d --name ff-builder docker.io/revenz/fileflows:latest
podman exec -u 0 ff-builder apt update 
podman exec -u 0 ff-builder apt install -y \
  ffmpeg vainfo mesa-va-drivers intel-media-va-driver-non-free
podman commit ff-builder localhost/fileflows-amd-vaapi:latest
podman rm -f ff-builder

# 5. Install all systemd units and enable services
sudo bash install/setup.sh

# 6. (Torrent fallback) Deploy Gluetun + qBittorrent
#    Copy torrent/.env.example to torrent/.env and fill in PIA credentials
#    then run: sudo bash torrent/verify-torrent-stack.sh
```

### Phase 2: Restore Configs from Backup

> **Config backup is the single most important restore step.** All app state,
> users, libraries, download history, and API keys live in
> `/home/skim/jellyfin-configs/`. If you have a backup, this phase takes
> minutes. Without it, you'll need to re-do every app's setup wizard.

**If you have a backup** (e.g., from NVMe or cloud storage):

```bash
# Stop all services first
sudo systemctl stop jellyfin jellyseerr sabnzbd prowlarr radarr sonarr bazarr
systemctl --user stop fileflows

# Restore configs (adjust source path to your backup location)
cp -a /path/to/backup/jellyfin-configs/* /home/skim/jellyfin-configs/

# Fix ownership
sudo chown -R 1000:1000 /home/skim/jellyfin-configs

# Restart
sudo systemctl start jellyfin jellyseerr sabnzbd prowlarr radarr sonarr bazarr
systemctl --user start fileflows
```

**Backup sources (as of Sep 2026):**
- **TV configs** — stored on MyCloud (kimshare), synced via rclone
- **Movies configs** — stored on internal NVMe backup
- **Full config tree** — `/home/skim/jellyfin-configs/` lives on NVMe RAID1;
  no off-device backup is automated. Copy it manually before drive swaps.

**No backup?** Skip to Phase 4 (first-time setup).

### Phase 3: Restore Media

> Media (movies, TV) lives on `/mnt/media`. If the USB array was destroyed, you
> must re-download everything — there is no off-site backup of the library
> itself.

If you have a **partial backup** (MyCloud has TV, NVMe has movies):

```bash
# Mount NVMe backup partition
# (adjust UUID to match your backup drive)
sudo mkdir -p /mnt/backup
sudo mount /dev/disk/by-uuid/<UUID> /mnt/backup

# Restore movies from NVMe
cp -a /mnt/backup/movies/* /mnt/media/movies/

# Restore TV from MyCloud via rclone
# (requires rclone + configured mycloud remote)
rclone copy mycloud:/Public/tv /mnt/media/tv/ \
  --progress --transfers 8 --checksum
```

Without any backup, start fresh — the download stack (SABnzbd + qBittorrent)
will re-populate everything as requests come in via Jellyseerr.

### Phase 4: First-Time Setup (No Config Backup)

If `/home/skim/jellyfin-configs/` was empty, follow the first-time setup steps
in README.md:

1. Complete each app's setup wizard (Jellyfin → SABnzbd → Prowlarr → Radarr →
   Sonarr → Bazarr → Jellyseerr)
2. Wire API keys between apps (see README.md "First-time setup" table)
3. Apply SABnzbd tunnel fix (whitelist + local_ranges)
4. Import FileFlows flows

Detailed per-app wiring: see `README.md` → **First-time setup** section.

### Phase 5: Cloudflare Tunnel

> **Requires:** Cloudflare API token (you provide — not in repo)

```bash
export CF_API_TOKEN='your-token-here'

# The install script creates the tunnel, DNS records, and systemd unit
bash cloudflare/install_tunnel.sh

# Create Cloudflare Access gates for admin services
bash cloudflare/setup_access.sh
```

**What the tunnel needs that isn't in the repo:**

| Item | Where it lands | How to get it |
|------|---------------|--------------|
| Tunnel credentials JSON | `~/.cloudflared/<tunnel-uuid>.json` | Generated by `cloudflared tunnel create` (part of install_tunnel.sh) |
| Cloudflare API token | Used at runtime by install script | Cloudflare dashboard |
| CF_ACCOUNT_ID | Used by access setup | Cloudflare dashboard |

After install, verify:

```bash
sudo systemctl status cloudflared
curl -s -o /dev/null -w "%{http_code}" http://localhost:8096
# Should return 200
```

### Phase 6: Smoke Test

```bash
# Check all services are running
sudo systemctl status jellyfin jellyseerr sabnzbd prowlarr radarr sonarr bazarr
systemctl --user status fileflows
systemctl --user status gluetun qbittorrent

# Run the health check script
bash scripts/media-stack-health.sh

# Verify tunnel is up
sudo journalctl -u cloudflared --no-pager -n 10

# Test external access
curl -s https://jellyfin.suvannmedia.com/ | head -5

# Submit a test request through Jellyseerr -> Radarr/Sonarr -> downloader
```

## Restoring from Drive Swap

> If the server survived but you're restoring from the temporary swap setup
> (Phase 1 from DRIVE-SWAP-RUNBOOK.md), the recovery path is:

```bash
# 1. Verify new array is mounted
df -h /var/mnt/media

# 2. Restore TV from MyCloud (may already be in place if you used FUSE)
rclone copy mycloud:/Public/tv /mnt/media/tv/ --progress --checksum

# 3. Restore movies from NVMe
cp -a /mnt/backup/movies/* /mnt/media/movies/

# 4. Run clean-up: remove temp mount units, disable backup services
#    See DRIVE-SWAP-RUNBOOK.md Phase 3
```

## Services Reference

| Service | Port | Image | Config path | Unit file |
|---------|------|-------|-------------|-----------|
| Jellyfin | 8096 | `jellyfin/jellyfin:latest` | `.../jellyfin/` | `systemd/jellyfin.service` |
| Jellyseerr | 5055 | `seerr/seerr:latest` | `.../jellyseerr/` | `systemd/jellyseerr.service` |
| SABnzbd | 8085 | `linuxserver/sabnzbd:latest` | `.../sabnzbd/` | `systemd/sabnzbd.service` |
| Prowlarr | 9696 | `linuxserver/prowlarr:latest` | `.../prowlarr/` | `systemd/prowlarr.service` |
| Radarr | 7878 | `linuxserver/radarr:latest` | `.../radarr/` | `systemd/radarr.service` |
| Sonarr | 8989 | `linuxserver/sonarr:latest` | `.../sonarr/` | `systemd/sonarr.service` |
| Bazarr | 6767 | `linuxserver/bazarr:latest` | `.../bazarr/` | `systemd/bazarr.service` |
| FileFlows | 5000 | `localhost/fileflows-amd-vaapi:latest` | `.../fileflows/` | `systemd/fileflows.service` (user unit) |
| Flaresolverr | 8191 | `flaresolverr/flaresolverr:latest` | — | `systemd/flaresolverr.service` |
| Gluetun | — | `qmcgaw/gluetun:latest` | `.../gluetun/` | `torrent/gluetun.service` (user unit) |
| qBittorrent | 8090 | `linuxserver/qbittorrent:latest` | `.../qbittorrent/` | `torrent/qbittorrent.service` (user unit) |
| Cloudflared | — | binary (not container) | — | `systemd/cloudflared.service` |

> All config paths under `/home/skim/jellyfin-configs/`. Torrent env vars in
> `torrent/.env` (PIA_USERNAME, PIA_PASSWORD, QB creds).

## Key Recovery Files

| File | Purpose |
|------|---------|
| `install/setup.sh` | Deploys all systemd units, enables services |
| `install/install_jellyfin.sh` | Jellyfin-specific unit deploy |
| `install/install_mergerfs.sh` | (Optional) mergerfs static binary install |
| `install/install_arr_stack.sh` | Arr stack unit deploy + FileFlows flow import |
| `systemd/*.service` | All system service unit files |
| `torrent/gluetun.service` | PIA tunnel unit |
| `torrent/qbittorrent.service` | Torrent client (binds to Gluetun namespace) |
| `torrent/verify-torrent-stack.sh` | Validates torrent setup post-deploy |
| `scripts/media-stack-health.sh` | Health check for all services |
| `scripts/media-stack-updater.sh` | Weekly container image updater |
| `scripts/fix-media-permissions.sh` | SELinux + ownership remediation |
| `cloudflare/config.yml.template` | Tunnel config template (needs UUID filled) |
| `cloudflare/install_tunnel.sh` | Cloudflare tunnel creation + DNS setup |
| `cloudflare/setup_access.sh` | Cloudflare Access gate setup |

## Cron Jobs

These cron jobs are configured via Hermes (not system crontab). After recovery,
re-register them if Hermes is restored:

| Schedule | Job | Purpose |
|----------|-----|---------|
| Mon 09:00 | `media-stack-updater` | Pull latest container images, restart services |
| Hourly | `media-stack-health` | Health check + remux watchdog (report only) |
| Mon 10:30 | `maintainer-report` | Weekly summary |

## Hermes Agent Recovery

> Hermes (the AI agent managing this server) is not required for the media stack
> to run — all services are autonomous systemd units. If Hermes is also being
> restored:

- Hermes config/profile: internal setup, not part of this repo
- Cron jobs run via Hermes, not system crontab
- Follow Hermes Agent documentation at https://hermes-agent.nousresearch.com/docs

## Key Gotchas

### SELinux blocks podman mounts
Container mounts to `/mnt/media` need `container_file_t` context:
```bash
sudo semanage fcontext -a -t container_file_t \
  '/var/mnt/media(/.*)?'
sudo restorecon -RF /var/mnt/media
```

### /home/skim must be 0711 for rootful podman
Rootful podman needs traverse permission on the user's home:
```bash
sudo chmod 711 /home/skim
```

### User/system service split
- **System units** (`sudo systemctl`) — Jellyfin, Arr stack, cloudflared
- **User units** (`systemctl --user`) — FileFlows, Gluetun, qBittorrent
- `loginctl enable-linger skim` keeps user units alive after logout

### Jellyseerr mounts to `/app/config`, not `/config`
Wrong path = setup wizard loops on every restart.
```bash
# Correct mount:
-v /home/skim/jellyfin-configs/jellyseerr:/app/config
```

### FileFlows must NOT have PUID/PGID
Under rootless podman, container uid 0 maps to host `skim` (1000). Setting
PUID=1000 makes the container process run as *container* uid 1000, which maps
to an **unmapped** subuid on the host → EACCES on every media write.

### `/mnt` is a symlink to `/var/mnt`
References to `/mnt/media` and `/var/mnt/media` are equivalent on this system.
Use whichever the unit file uses; do not mix in the same file.

### Flaresolverr
Runs as a separate container (not integrated into Prowlarr). Prowlarr's indexers
point to `http://localhost:8191` as a generic HTTP proxy. Flaresolverr bypasses
Cloudflare challenge pages on indexer web UIs.

### Power blip recovery
After power loss, services may hit restart limits:
```bash
sudo systemctl reset-failed
sudo systemctl --failed
systemctl --user reset-failed fileflows gluetun qbittorrent
```

## Version History

| Date | Change |
|------|--------|
| Sep 2026 | Initial DR guide — covers full rebuild from scratch |
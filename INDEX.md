# suvannmedia media stack repository

This repository contains the deployable configuration and recovery material for
the current Bazzite media stack.

- `install/setup.sh` — master installer for the production stack
- `install/install_jellyfin.sh` — Jellyfin system-unit deployment
- `install/install_arr_stack.sh` — Arr services and FileFlows user-unit deployment
- `systemd/` — deployable system and user unit sources
- `torrent/` — Gluetun + qBittorrent user units and verification
- `cloudflare/` — system Cloudflared unit, tunnel template, and setup scripts
- `fileflows/flows/` — checked-in FileFlows pipeline
- `scripts/` — health check, updater, and media-permission remediation
- `docs/CLEANUPARR.md` — Cleanuparr queue-monitor configuration and recovery
- `docs/RECOVERY.md` — production recovery procedure

Media is the single ext4 filesystem at `/var/mnt/pool1` on the hardware-RAID5
USB enclosure. Application state and FileFlows runner scratch remain on the
internal NVMe at `/home/skim/jellyfin-configs`.

The retired mergerfs pool, drive-swap mount units, temporary rclone mount, and
legacy external-config mount are intentionally not represented here.

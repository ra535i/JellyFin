# suvannmedia media stack

Production configuration for the Bazzite media server. This repository is the
source of truth for the deployed systemd units, install scripts, Cloudflare
tunnel template, FileFlows flow, and operational checks.

## Production architecture

- **Media:** the single ext4 filesystem at `/var/mnt/pool1` (also reachable as
  `/mnt/pool1`) on the SSI hardware-RAID5 USB enclosure.
- **Application state:** `/home/skim/jellyfin-configs` on the internal NVMe.
  It holds every application database, configuration directory, cache, and the
  FileFlows runner scratch directory.
- **Containers:** rootful, system-level Podman units for Jellyfin, the Arr
  apps, Flaresolverr, and Cloudflared. FileFlows, Gluetun, and qBittorrent are
  rootless user units for `skim`.
- **Ingress:** Cloudflare Tunnel publishes the suvannmedia.com endpoints.
  qBittorrent shares Gluetun's network namespace; only Gluetun exposes its
  WebUI on `127.0.0.1:8090`, so the torrent client cannot bypass PIA.

`mergerfs`, the temporary drive-swap mounts, the temporary rclone TV mount,
and the legacy external-config mount are not part of this stack and are
intentionally absent from this repository.

## Services

- Jellyfin — `8096` — `docker.io/jellyfin/jellyfin:latest`
- Jellyseerr — `5055` — `docker.io/seerr/seerr:v3.4.1` (config is `/app/config`)
- SABnzbd — `8085` — `docker.io/linuxserver/sabnzbd:latest`
- Prowlarr — `9696` — `docker.io/linuxserver/prowlarr:latest`
- Radarr — `7878` — `docker.io/linuxserver/radarr:latest`
- Sonarr — `8989` — `docker.io/linuxserver/sonarr:latest`
- Bazarr — `6767` — `docker.io/linuxserver/bazarr:latest`
- Flaresolverr — `8191`, internal only — `docker.io/flaresolverr/flaresolverr:latest`
- FileFlows — `5000` — `localhost/fileflows-amd-vaapi:latest`
- Gluetun — PIA OpenVPN, rootless user service
- qBittorrent — exposed through Gluetun on `8090`, rootless user service
- Cloudflared — system service; see `cloudflare/config.yml.template`

The live tunnel routes `jellyfin`, `jellyseerr`, `sabnzbd`, `prowlarr`,
`radarr`, `sonarr`, `bazarr`, `fileflows`, and `qbittorrent` under
`suvannmedia.com`. Flaresolverr has no public route.

## Storage and SELinux invariants

Do not move application databases onto the USB media volume. Keep
`/home/skim/jellyfin-configs/fileflows/runner-temp` on the NVMe: FileFlows
runner startup is metadata-heavy and RAID-backed scratch causes severe startup
latency even for no-op work.

Rootful containers need traversal permission and a persistent SELinux label:

```bash
sudo chmod 711 /home/skim
sudo semanage fcontext -a -t container_file_t \
  '/var/home/skim/jellyfin-configs(/.*)?'
sudo restorecon -RF /var/home/skim/jellyfin-configs
```

The media mounts in the rootful units use `:z` where required. Do not add `:z`
to the rootless FileFlows media mount.

## Deploy or recover

1. Mount the production media filesystem at `/var/mnt/pool1`.
2. Clone this repository and prepare `/home/skim/jellyfin-configs` with the
   label above.
3. Build the FileFlows image if it is not already present:

```bash
podman run -d --name ff-builder docker.io/revenz/fileflows:latest
podman exec -u 0 ff-builder apt update
podman exec -u 0 ff-builder apt install -y \
  ffmpeg vainfo mesa-va-drivers intel-media-va-driver-non-free
podman commit ff-builder localhost/fileflows-amd-vaapi:latest
podman rm -f ff-builder
```

4. Install the system and FileFlows units:

```bash
sudo bash install/setup.sh
```

5. For torrent fallback, copy `torrent/.env.example` to the gitignored
   `torrent/.env`, then follow `torrent/README.md`.
6. Configure or restore the Cloudflare tunnel with
   `cloudflare/install_tunnel.sh`.

The installer creates the FileFlows NVMe scratch directory, deploys the system
units, enables the FileFlows user unit with lingering, and performs localhost
HTTP probes. It does not store credentials.

## FileFlows flow

`fileflows/flows/20Mbps Bitrate V4.json` is the checked-in flow. It caps video
above 20 Mbps using VAAPI with CPU fallback, preserves the HDR-oriented media
workflow, and normalizes compatible AC3/EAC3 5.1 audio. Import it with
`fileflows/import_flows.sh` if the existing FileFlows database was not restored.

## Operations

- `scripts/media-stack-health.sh` checks the `/var/mnt/pool1` mount, service
  HTTP endpoints, and failed units. It is intentionally silent when healthy.
- `scripts/media-stack-updater.sh` updates latest-tagged images and Cloudflared.
  Jellyseerr remains pinned to `v3.4.1` in the deployed unit.
- `scripts/fix-media-permissions.sh` repairs ownership/SELinux issues.
- `docs/RECOVERY.md` is the disaster-recovery procedure.

Never put passwords, API keys, tunnel credentials, or application databases in
the repository.

# Disaster recovery — suvannmedia stack

This procedure restores the production Bazzite media stack. It deliberately
matches the live layout: a single `/var/mnt/pool1` ext4 media filesystem and
NVMe-backed application state at `/home/skim/jellyfin-configs`.

## Prerequisites

Provide these outside the repository:

- Cloudflare API token and tunnel credentials
- PIA OpenVPN credentials (only when restoring torrent fallback)
- Service/API credentials recovered from the application-config backup or
  recreated in the application UIs
- A mounted production media filesystem at `/var/mnt/pool1`

No credential, application database, or backup archive belongs in git.

## 1. Prepare Bazzite and clone

```bash
sudo dnf install -y git podman
sudo mkdir -p /var/mnt/pool1
# Mount the production media filesystem here before starting services.
git clone https://github.com/ra535i/JellyFin.git /home/skim/JellyFin
cd /home/skim/JellyFin
```

## 2. Restore or create application state

Restore `/home/skim/jellyfin-configs` from its backup before starting services
when possible. Otherwise create it and complete first-run setup in each app.

```bash
mkdir -p /home/skim/jellyfin-configs/fileflows/runner-temp
sudo chown -R skim:skim /home/skim/jellyfin-configs
chmod 0775 /home/skim/jellyfin-configs/fileflows/runner-temp
sudo chmod 711 /home/skim
sudo semanage fcontext -a -t container_file_t \
  '/var/home/skim/jellyfin-configs(/.*)?' || \
  sudo semanage fcontext -m -t container_file_t \
  '/var/home/skim/jellyfin-configs(/.*)?'
sudo restorecon -RF /var/home/skim/jellyfin-configs
```

Keep FileFlows `runner-temp` on this NVMe path. It must not be relocated onto
`/var/mnt/pool1`: plugin startup is metadata-heavy and RAID-backed scratch
causes extreme latency before processing begins.

## 3. Build the FileFlows image

```bash
podman run -d --name ff-builder docker.io/revenz/fileflows@sha256:1f412e4e2b411a18d25538095629ef870185ea602f9840caab06088dec8231ae
podman exec -u 0 ff-builder apt update
podman exec -u 0 ff-builder apt install -y \
  ffmpeg vainfo mesa-va-drivers intel-media-va-driver-non-free
podman commit ff-builder localhost/fileflows-amd-vaapi:latest
podman rm -f ff-builder
```

## 4. Deploy the stack

```bash
sudo bash install/setup.sh
```

This deploys system units for Jellyfin, Jellyseerr, SABnzbd, Prowlarr, Radarr,
Sonarr, Bazarr, and Flaresolverr. It deploys FileFlows as a lingering `skim`
user unit. Validate the torrent user units separately after creating the
credential file:

```bash
cp torrent/.env.example torrent/.env
# Add the PIA values locally; torrent/.env is gitignored.
# Follow torrent/README.md, then run:
bash torrent/verify-torrent-stack.sh
```

## 5. Restore Cloudflare Tunnel

```bash
export CF_API_TOKEN='set-this-in-your-shell'
bash cloudflare/install_tunnel.sh
```

The template includes every live public endpoint: Jellyfin, Jellyseerr,
SABnzbd, Prowlarr, Radarr, Sonarr, Bazarr, FileFlows, and qBittorrent. Do not
publish Flaresolverr.

## 6. Verify the restored stack

```bash
bash scripts/media-stack-health.sh
for port in 8096 5055 8085 9696 7878 8989 6767 8191 5000 8090; do
  printf '%s: ' "$port"
  curl --max-time 8 -sS -o /dev/null -w '%{http_code}\n' \
    "http://127.0.0.1:$port/"
done
podman inspect fileflows --format '{{range .Mounts}}{{if eq .Destination "/temp"}}{{.Source}}{{end}}{{end}}'
```

Expected HTTP responses may be redirects (for example Jellyfin and the Arr
apps); a connection failure is the fault condition. The FileFlows inspection
must print `/home/skim/jellyfin-configs/fileflows/runner-temp`.

## Important invariants

- `/mnt` is a symlink to `/var/mnt`; use `/var/mnt/pool1` in production units.
- Jellyseerr config mounts at `/app/config`, not `/config`.
- qBittorrent must remain in Gluetun's network namespace; do not give it host
  networking.
- FileFlows must not receive `PUID`/`PGID`. In rootless Podman, leaving them
  unset maps its container-root process correctly to host user `skim`.
- The legacy mergerfs pool, temporary drive-swap units, and temporary rclone
  mounts are retired and must not be restored.

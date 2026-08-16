# Media Server — Bazzite

Jellyfin + *Arr stack on Bazzite (immutable Fedora). All services run as
systemd-managed podman containers. Exposed externally via Cloudflare Tunnel
with Cloudflare Access gating admin services.

Survives reboots, survives OS updates. Rebuild from scratch in under an hour.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ USB Drives                                                    │
│  sda1 (2.7T)  sdb1 (2.7T)  sdc1 (2.7T)                      │
│      └──── mergerfs pool ──── /mnt/media (8.1T)              │
│                                       │                       │
│                              ┌────────┴────────┐              │
│                              │                 │              │
│                         /mnt/media/       /mnt/media/         │
│                         movies/           tv/                 │
│                              │                 │              │
│   sdd1 (500GB) ── /mnt/jellyfin/ (configs, cache, metadata)   │
│                              │                                │
│  Radarr → Sonarr → Prowlarr → SABnzbd → Downloads → import   │
│                              │                                │
│  Jellyfin (streaming) ← Jellyseerr (family requests)          │
│                              │                                │
│  Cloudflare Tunnel ── suvannmedia.com                          │
│     ├── jellyfin.suvannmedia.com  (OPEN — mobile apps)         │
│     ├── jellyseerr.suvannmedia.com (OPEN — family)             │
│     ├── sabnzbd.suvannmedia.com   (Access gate)                │
│     ├── prowlarr.suvannmedia.com  (Access gate)                │
│     ├── radarr.suvannmedia.com    (Access gate)                │
│     ├── sonarr.suvannmedia.com    (Access gate)                │
│     └── bazarr.suvannmedia.com    (Access gate)                │
└──────────────────────────────────────────────────────────────┘
```

## Services

| Service    | Port  | Purpose                     | External                 | Auth             |
|------------|-------|-----------------------------|--------------------------|------------------|
| Jellyfin   | 8096  | Media streaming             | jellyfin.suvannmedia.com | Open (Jellyfin)  |
| Jellyseerr | 5055  | Family request portal       | jellyseerr.suvannmedia.com | Open (Jellyfin)|
| SABnzbd    | 8085  | Usenet downloader           | sabnzbd.suvannmedia.com  | Access gate      |
| Prowlarr   | 9696  | Indexer management          | prowlarr.suvannmedia.com | Access gate      |
| Radarr     | 7878  | Movie automation            | radarr.suvannmedia.com   | Access gate      |
| Sonarr     | 8989  | TV automation               | sonarr.suvannmedia.com   | Access gate      |
| Bazarr     | 6767  | Subtitle automation         | bazarr.suvannmedia.com   | Access gate      |

## Prerequisites

Before you start, you'll need:

1. **Hardware** — 3x USB drives (pool), 1x SSD/HDD (config)
2. **Domain** — registered at Cloudflare ($8–12/yr)
3. **Usenet provider** — Frugal Usenet (~$5/mo)
4. **Indexer** — NZBGeek (~$10/yr)
5. **TMDb API key** — free from themoviedb.org

## Quick rebuild (fresh Bazzite install)

```bash
# 1. Clone this repo
sudo dnf install -y git
git clone https://github.com/ra535i/JellyFin.git /opt/jellyfin
cd /opt/jellyfin

# 2. Mount your drives
#    Edit /etc/fstab with your drive UUIDs from blkid(8)
#    Mount points: /mnt/pool1, /mnt/pool2, /mnt/pool3, /mnt/jellyfin
sudo mount -a

# 3. Run the stack installer
sudo bash install/install_mergerfs.sh   # mergerfs pool from 3 drives
sudo bash install/setup.sh               # Jellyfin + Arr stack
```

Your existing configs on `/mnt/jellyfin/config/` are preserved — all apps come
back with their same settings, users, libraries, and API keys.

## First-time setup (from scratch, no configs)

If `/mnt/jellyfin/config/` is empty (truly fresh build), you'll also need:

### Step 1: Apply SABnzbd tunnel fix

SABnzbd blocks external access by default. Since it's behind Cloudflare Tunnel,
the requests appear to come from Cloudflare's IPs. Edit the config:

```ini
# /mnt/jellyfin/config/sabnzbd/sabnzbd.ini
host_whitelist = bazzite, sabnzbd.suvannmedia.com
local_ranges = 0.0.0.0/0
```

Then restart: `sudo systemctl restart sabnzbd`

### Step 2: Wire the apps together

After the initial config of each app:

| Step | What | How |
|------|------|-----|
| 1 | SABnzbd | Config → General → Enable API key (copy it) |
| 2 | Prowlarr | Settings → Apps → Add Radarr + Sonarr + SABnzbd |
| 3 | Radarr | Settings → Download Client → Add SABnzbd (paste key) |
| 4 | Radarr | Settings → Indexers → Add Prowlarr |
| 5 | Radarr | Settings → Media Management → Root folder → `/movies` |
| 6 | Sonarr | Same as Radarr but root folder → `/tv` |
| 7 | Jellyseerr | Settings → Jellyfin → Connect (URL + API key) |
| 8 | Jellyseerr | Settings → Radarr/Sonarr → Connect |
| 9 | Bazarr | Settings → Radarr/Sonarr → Connect |
| 10 | Bazarr | Subtitles → Provider → Add Opensubtitles etc. |

### Step 3: Expose externally via Cloudflare Tunnel

```bash
# Set your API token
export CF_API_TOKEN='your-token-here'

# Install tunnel + create DNS records
bash cloudflare/install_tunnel.sh

# Create Access gates for admin services
bash cloudflare/setup_access.sh
```

These scripts handle:
- Downloading cloudflared
- Authenticating with your Cloudflare API token
- Creating the tunnel + credentials
- Setting up DNS CNAME records (jellyfin, jellyseerr, sabnzbd, prowlarr, radarr, sonarr, bazarr)
- Installing a user systemd service (survives reboot with linger)

> **Note:** `install_tunnel.sh` expects `config.yml.template` to be customized.
> Edit `cloudflare/config.yml.template` with your tunnel name and domain first.

## Cloudflare Access

Admin services (SABnzbd, Prowlarr, Radarr, Sonarr, Bazarr) are gated behind
Cloudflare Access with Google OAuth. Only `suvann540i@gmail.com` is allowed.

Jellyfin and Jellyseerr are **open** (no Access gate) so mobile apps and family
can connect without authentication.

## Port notes

- **SABnzbd** runs on **8085** (container config sets `port = 8085` in sabnzbd.ini,
  not the default 8080). This is set in the container's persistent config,
  not in the systemd unit.
- All services use `--network host` — no port mapping needed in docker args.

## Rebuilding from total disaster

If the entire machine dies:

1. Install Bazzite fresh
2. Mount your drives (still partitioned, same UUIDs — just add to fstab)
3. `git clone https://github.com/ra535i/JellyFin.git`
4. `sudo bash install/install_mergerfs.sh`
5. `sudo bash install/setup.sh`
6. Apply SABnzbd tunnel fix (Step 1 above)
7. Deploy tunnel + Access: `bash cloudflare/install_tunnel.sh && bash cloudflare/setup_access.sh`
8. All app configs on `/mnt/jellyfin/config/` — they come back with everything intact

## Cost breakdown

| Item | Cost |
|------|------|
| Domain (suvannmedia.com) | $8–12/yr |
| Cloudflare Tunnel | Free |
| Cloudflare Access (up to 50 users) | Free |
| Usenet (Frugal) | ~$5/mo |
| Indexer (NZBGeek) | ~$10/yr |
| **Total** | **~$15/mo** |

Vs. streaming subs that'd cost 3× that.
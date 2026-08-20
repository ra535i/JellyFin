# Media Server — Bazzite

Jellyfin + *Arr stack on Bazzite (immutable Fedora). All services run as
systemd-managed podman containers (`--network host`). Exposed externally via
Cloudflare Tunnel with Cloudflare Access gating admin services.

Survives reboots, survives OS updates. Rebuild from scratch in under an hour.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│ USB Drives                                                            │
│  sda1 (2.7T)  sdb1 (2.7T)  sdc1 (2.7T)                              │
│      └── mergerfs pool ─── /mnt/media (8.1T) ─── sdd1 (500GB SSD)    │
│                                    │                    │             │
│                            ┌───────┴────────┐        /var/mnt/jellyfin│
│                            │                │    (systemd .mount unit) │
│                       movies/            tv/    ┌── config/ ─────────┐│
│                         │                │      │  jellyfin          ││
│                         │                │      │  sabnzbd           ││
│                         │                │      │  prowlarr          ││
│  Radarr ──▶ Sonarr ──▶ Prowlarr ──▶ SABnzbd ── downloads/          ││
│                                            │      │  radarr           ││
│               FileFlows ── (transcode pipeline)   │  sonarr           ││
│     REMUX ─▶ HEVC VAAPI ─▶ 20Mbps Bitrate        │  bazarr           ││
│     VAAPI fail ──▶ CPU fallback                   │  jellyseerr      ││
│                    │                              │  fileflows       ││
│  Jellyfin (streaming) ◀── Jellyseerr (requests)   └───────────────────┘│
│                    │                                                    │
│               Cloudflare Tunnel ─── suvannmedia.com                    │
│                  ├── jellyfin.suvannmedia.com   (OPEN — mobile apps)    │
│                  ├── jellyseerr.suvannmedia.com (OPEN — family)        │
│                  ├── sabnzbd.suvannmedia.com    (Access gate)          │
│                  ├── prowlarr.suvannmedia.com   (Access gate)          │
│                  ├── radarr.suvannmedia.com     (Access gate)          │
│                  ├── sonarr.suvannmedia.com     (Access gate)          │
│                  ├── bazarr.suvannmedia.com     (Access gate)          │
│                  └── fileflows.suvannmedia.com  (Access gate)          │
└──────────────────────────────────────────────────────────────────────┘
```

## Services

| Service    | Port  | Image                                   | Mounts to                    | External                     | Auth             |
|------------|-------|-----------------------------------------|------------------------------|------------------------------|------------------|
| Jellyfin   | 8096  | `docker.io/jellyfin/jellyfin:latest`    | `/config`                    | jellyfin.suvannmedia.com     | Open (Jellyfin)  |
| Jellyseerr | 5055  | `fallenbagel/jellyseerr:latest`         | **`/app/config`** ⚠️         | jellyseerr.suvannmedia.com   | Open (Jellyfin)  |
| SABnzbd    | 8085  | `linuxserver/sabnzbd:latest`            | `/config`                    | sabnzbd.suvannmedia.com      | Access gate      |
| Prowlarr   | 9696  | `linuxserver/prowlarr:latest`           | `/config`                    | prowlarr.suvannmedia.com     | Access gate      |
| Radarr     | 7878  | `linuxserver/radarr:latest`             | `/config`                    | radarr.suvannmedia.com       | Access gate      |
| Sonarr     | 8989  | `linuxserver/sonarr:latest`             | `/config`                    | sonarr.suvannmedia.com       | Access gate      |
| Bazarr     | 6767  | `linuxserver/bazarr:latest`             | `/config`                    | bazarr.suvannmedia.com       | Access gate      |
| FileFlows  | 5000  | `localhost/fileflows-amd-vaapi:latest`  | `/app/Data`                  | fileflows.suvannmedia.com    | Access gate      |

> **Jellyseerr gotcha:** Jellyseerr expects its config mounted at **`/app/config`**,
> NOT `/config`. Mounting to the wrong path causes the first-boot setup wizard to
> loop. The correct unit mount is `-v /mnt/jellyfin/config/jellyseerr:/app/config`.

> **All services** use `--network host` — no port mapping needed.
> All run as `User=1000:1000` (container UID is `1000:1000`).
> FileFlows additionally runs as **`User=skim`** at the systemd level so podman
> can access the locally-built `localhost/` image.

## Disk Layout

| Drive     | Size  | Mount                     | Purpose                        |
|-----------|-------|---------------------------|--------------------------------|
| sdd1      | 465GB | `/var/mnt/jellyfin`       | Configs, cache, metadata       |
| sda1/sdb1/sdc1 | 8.1T | `/mnt/media` (mergerfs) | Movies, TV, downloads          |

### SSD mount via systemd (not fstab)

The config SSD mounts at `/var/mnt/jellyfin` (canonical path) via a systemd
mount unit, NOT fstab. This ensures the mount is ready before any container
starts. All 9 service units include `RequiresMountsFor=/var/mnt/jellyfin`.

The symlink `/mnt/jellyfin -> /var/mnt/jellyfin` exists for compatibility
but the canonical path is `/var/mnt/jellyfin`.

```ini
# /etc/systemd/system/var-mnt-jellyfin.mount
[Unit]
Description=Jellyfin SSD (465GB)
Before=local-fs.target

[Mount]
What=/dev/disk/by-uuid/9cdfea3c-e6bb-41a8-928b-583f3051d7bf
Where=/var/mnt/jellyfin
Type=ext4
Options=defaults

[Install]
WantedBy=local-fs.target
```

> **Why `Before=local-fs.target`?** Avoids an ordering cycle with systemd's
> internal dependency graph. The unit works correctly once loaded via
> `systemctl daemon-reload && systemctl enable --now var-mnt-jellyfin.mount`.

### Mergerfs pool

Three USB drives pooled via mergerfs (static binary, no rpm-ostree layering):

```ini
# /etc/systemd/system/mergerfs.service
[Service]
ExecStart=/usr/local/bin/mergerfs -o defaults,allow_other,use_ino,hard_remove,dropcacheonclose=true,category.create=mfs,cache.files=partial,moveonenospc=true /mnt/pool1:/mnt/pool2:/mnt/pool3 /mnt/media
```

Installed via `install/install_mergerfs.sh` which downloads the static binary
from GitHub releases (no rpm-ostree layer needed on immutable Fedora).

## Prerequisites

Before you start, you'll need:

1. **Hardware** — 3x USB drives (pool), 1x SSD (config)
2. **Domain** — registered at Cloudflare ($8–12/yr)
3. **Usenet provider** — Frugal Usenet (~$5/mo)
4. **Indexer** — NZBGeek (~$10/yr)
5. **TMDb API key** — free from themoviedb.org

## Quick rebuild (fresh Bazzite install)

```bash
# 1. Install git + podman (dnf is stock on Bazzite)
sudo dnf install -y git podman
git clone https://github.com/ra535i/JellyFin.git /opt/jellyfin
cd /opt/jellyfin

# 2. Mount the config SSD via systemd unit
sudo cp systemd/var-mnt-jellyfin.mount /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now var-mnt-jellyfin.mount

# 3. Install mergerfs pool (static binary, no rpm-ostree)
sudo bash install/install_mergerfs.sh

# 4. Build the custom FileFlows image (needs ffmpeg + VAAPI)
podman run -d --name ff-builder docker.io/revenz/fileflows:latest
podman exec -u 0 ff-builder apt update && apt install -y \
  ffmpeg vainfo mesa-va-drivers intel-media-va-driver-non-free
podman commit ff-builder localhost/fileflows-amd-vaapi:latest
podman rm -f ff-builder

# 5. Install the full stack (Jellyfin + Arr + FileFlows)
sudo bash install/setup.sh
```

Your existing configs on `/var/mnt/jellyfin/config/` are preserved — all apps
come back with their same settings, users, libraries, and API keys.

## First-time setup (from scratch, no configs)

If `/var/mnt/jellyfin/config/` is empty (truly fresh build).

### Step 1: Apply SABnzbd tunnel fix

SABnzbd blocks external access by default. Since it's behind Cloudflare Tunnel,
the requests appear to come from Cloudflare's IPs. Edit the config:

```ini
# /var/mnt/jellyfin/config/sabnzbd/sabnzbd.ini
host_whitelist = bazzite, sabnzbd.suvannmedia.com
local_ranges = 0.0.0.0/0
port = 8085
```

Then restart: `sudo systemctl restart sabnzbd`

### Step 2: Wire the apps together

After the initial setup wizard of each app:

| Step | What | How |
|------|------|-----|
| 1 | **SABnzbd** | Config → General → Enable API key (copy it) |
| 2 | **Prowlarr** | Settings → Apps → Add Radarr + Sonarr + SABnzbd (paste API key) |
| 3 | **Radarr** | Settings → Download Client → Add SABnzbd (paste key) |
| 4 | **Radarr** | Settings → Indexers → Add Prowlarr |
| 5 | **Radarr** | Settings → Media Management → Root folder → `/movies` |
| 6 | **Sonarr** | Same as Radarr but root folder → `/tv` |
| 7 | **Jellyseerr** | Settings → Jellyfin → Connect (URL: `http://localhost:8096` + API key) |
| 8 | **Jellyseerr** | Settings → Radarr/Sonarr → Connect |
| 9 | **Bazarr** | Settings → Radarr/Sonarr → Connect |
| 10 | **Bazarr** | Subtitles → Provider → Add Opensubtitles etc. |

### Step 3: Expose externally via Cloudflare Tunnel

```bash
# Set your API token
export CF_API_TOKEN='your-token-here'

# Install tunnel, sync binary to system path, create DNS records
bash cloudflare/install_tunnel.sh

# Create Access gates for admin services
bash cloudflare/setup_access.sh
```

The `install_tunnel.sh` script performs the full setup:

1. Downloads `cloudflared` binary to `~/.local/bin/`
2. Authenticates with the Cloudflare API token
3. Creates or reuses the tunnel + credentials
4. Creates DNS CNAME records for all 8 subdomains
5. **Copies the binary to `/usr/local/bin/cloudflared`**
6. **Installs a system-level systemd service** (not user-level)
7. Starts the tunnel

```ini
# /etc/systemd/system/cloudflared.service
[Unit]
Description=Cloudflare Tunnel for suvannmedia.com
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=skim
ExecStart=/usr/local/bin/cloudflared tunnel --config /home/skim/.cloudflared/config.yml run
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

> **Note:** The tunnel was converted from user-level to system-level because
> user services sometimes fail to start reliably at boot. The system-level
> service starts consistently after every reboot.

> **Edit first:** `cloudflare/config.yml.template` needs your tunnel UUID
> and credentials-file path customized. The install script does this
> automatically, but inspect it first if you're troubleshooting.

## Cloudflare Access

Admin services (SABnzbd, Prowlarr, Radarr, Sonarr, Bazarr, FileFlows) are gated
behind Cloudflare Access with Google OAuth. Only `suvann540i@gmail.com` is
allowed.

Jellyfin and Jellyseerr are **open** (no Access gate) so mobile apps and family
can connect without authentication.

> **Note:** Access gate is currently blocked (remedial operation pending after
> Aug 2026 incident). Services are still exposed but Access enforcement is not
> active.

## FileFlows Pipeline

### Current flow: "20Mbps Bitrate V4" (Revision 8)

The decision tree:

```
                     Video File
                         │
                    [Bitrate > 20Mbps?]
                     │              │
                   YES             NO
                     │              │
              Movie Lookup    [TrueHD audio check?]
                     │          │              │
            FFMPEG Builder    YES            NO
                     │          │              │
            Remux to MKV    FFMPEG Builder   Complete Flow
                     │     (audio only)     (file unchanged)
          HEVC VAAPI Encode     │
                     │     Strip non-eng subs
       Bitrate Encode HEVC     │
        VAAPI @ 20Mbps     Set language eng
                     │          │
          Strip non-eng subs    │
                     │     AC3 5.1 audio
          Set language eng     (eng/kor/jpn/zho/tha)
                     │          │
          AC3 5.1 audio     Remove TrueHD
        (eng/kor/jpn/zho/tha)  │
                     │     Replace Original
          Remove TrueHD
                     │
               Executor
                     │
            Replace Original
```

**Detailed pipeline for files over 20Mbps:**

1. **Video File** — Input file detected
2. **Bitrate > 20Mbps gate** — Check whether the video bitrate exceeds 20 Mbps
3. **Movie Lookup** — TMDb lookup (folder name as search query)
4. **FFMPEG Builder: Start** — Begin ffmpeg processing
5. **Remux to MKV** — Remux container to MKV
6. **HEVC VAAPI Encode** — Encode video to HEVC via hardware VAAPI
7. **Cap Bitrate at 20Mbps** — Enforce 20 Mbps bitrate ceiling
8. **Strip non-eng subs** — Remove subtitle languages other than English
9. **Set language eng** — Set default audio/subtitle language to English
10. **AC3 5.1 audio** — Convert audio to AC3 5.1 (eng/kor/jpn/zho/tha)
11. **Remove TrueHD** — Strip TrueHD track (redundant after AC3 exists)
12. **FFMPEG Builder: Executor** — Run the ffmpeg transcode
13. **Replace Original** — Overwrite source with transcoded file

On VAAPI failure → **CPU Fall-back Encode** → CPU Executor → Replace Original.

**For files under 20 Mbps:**

- **TrueHD audio check** — If TrueHD audio present: run an audio-only pipeline
  to strip TrueHD and ensure AC3 5.1
- **No TrueHD** → **Complete Flow** — File passes through unchanged

**Flow file:** `fileflows/flows/20Mbps_Bitrate_V4.json`

### Importing flows

The `install_arr_stack.sh` script automatically copies flow files into the
FileFlows container and runs the import script. To re-import manually:

```bash
podman cp /home/skim/JellyFin/fileflows/flows fileflows:/tmp/flows
podman cp /home/skim/JellyFin/fileflows/import_flows.sh fileflows:/tmp/
podman exec fileflows bash /tmp/import_flows.sh
```

> **Note:** The API import (`/api/flow/import`) can be flaky. If flows don't
> appear in the UI after import, add them manually via the FileFlows web UI
> (FileFlows → Flows → Add → Import Flow from JSON).

## Systemd Service Files

All service files live in `systemd/` and are deployed to `/etc/systemd/system/`.

| File | Purpose |
|------|---------|
| `var-mnt-jellyfin.mount` | SSD mount unit (canonical path `/var/mnt/jellyfin`) |
| `mergerfs.service` | mergerfs pool from 3 USB drives |
| `jellyfin.service` | Jellyfin media server |
| `jellyseerr.service` | Jellyseerr request portal (**mounts to `/app/config`**) |
| `sabnzbd.service` | SABnzbd usenet downloader |
| `prowlarr.service` | Prowlarr indexer manager |
| `radarr.service` | Radarr movie automation |
| `sonarr.service` | Sonarr TV automation |
| `bazarr.service` | Bazarr subtitle automation |
| `fileflows.service` | FileFlows media processing (**User=skim, TimeoutStartSec=300**) |
| `cloudflared.service` | Cloudflare Tunnel (system-level, not user-level) |

### Key systemd quirks

- **FileFlows** has `TimeoutStartSec=300` because the custom image reinstall
  VAAPI packages at first boot (apt install ffmpeg/vainfo/VA drivers). Without
  this, systemd kills the startup after the default 90s timeout.
- **FileFlows** runs as `User=skim` (not root) so `podman` can access the
  `localhost/fileflows-amd-vaapi:latest` image (local images owned by the user).
- **FileFlows** uses both `ExecStop` (`podman stop -t 10 fileflows`) and
  `ExecStopPost` (`podman rm -f fileflows`) instead of `--rm` because
  `User=skim` mode makes podman stop/rm tricky in the restart cycle.
- **The abort.conf drop-in** (`/etc/systemd/system/service.d/10-timeout-abort.conf`)
  sets `TimeoutStopFailureMode=abort`, which sends SIGABRT to any service that
  fails to stop in time. This can cause surprising coredumps. To disable:
  ```bash
  sudo mkdir -p /etc/systemd/system/service.d
  sudo ln -sv /dev/null /etc/systemd/system/service.d/10-timeout-abort.conf
  ```
- **Power blips** require `systemctl reset-failed <service>` before a service
  that hit its restart limit will try again.

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

## Lessons Learned

### Jellyseerr mount path
Jellyseerr expects config at **`/app/config`** inside the container, NOT
`/config`. The container banner warns when mounted to the wrong path
("no configuration directory found"). If the setup wizard loops on first boot,
check that the systemd service mounts to `/app/config`:

```
-v /mnt/jellyfin/config/jellyseerr:/app/config
```

### FileFlows custom image + TimeoutStartSec
The `fileflows-amd-vaapi:latest` image is built on top of the stock
`revenz/fileflows` by installing ffmpeg and VAAPI drivers. These packages are
reinstalled every time the container starts (not baked into layers), which can
take 2+ minutes. The systemd unit sets `TimeoutStartSec=300` to compensate.

### FileFlows User=skim
FileFlows runs with `User=skim` at the systemd level (not root). This is
necessary because `podman run` as root can't see locally-built images in the
`localhost/` namespace — those are user-scoped. The tradeoff is that `--rm`
doesn't work as reliably for cleanup, so `ExecStop + ExecStopPost` are used
explicitly.

### Power blip recovery
After a sudden power loss, systemd services enter `failed` state and won't
restart automatically (restart limit exhausted). Recovery:

```bash
sudo systemctl reset-failed fileflows
sudo systemctl restart fileflows
# Repeat for any other failed services
sudo systemctl --failed
```

### Cloudflare tunnel user→system migration
The tunnel originally ran as a user-level systemd service (via `systemctl
--user` with lingering). It was migrated to a system-level service because
user services sometimes fail to start at boot, leaving the server inaccessible
after a power outage. The binary was copied from `~/.local/bin/cloudflared` to
`/usr/local/bin/cloudflared` for system-level execution.
# Media Server — Bazzite

Jellyfin + *Arr stack on Bazzite (immutable Fedora). All services run as
systemd-managed podman containers (`--network host`). Exposed externally via
Cloudflare Tunnel. Cloudflare Access is intended to gate the admin services
(gating currently NOT enforced — see Cloudflare Access section).

Survives reboots, survives OS updates. Rebuild from scratch in under an hour.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│Storage                                                               │
│ 5.5T USB enclosure (SSI H/W RAID5) --> /mnt/media (ext4)             │
│(mergerfs 3-drive pool retired Sept 2026 -- see Media storage)        │
│                                                                      │
│  movies/   tv/   downloads/   fileflows-working/                     │
│                                                                      │
│Jellyseerr (requests) --> Radarr / Sonarr --> Prowlarr (indexers)     │
│                 |                                                    │
│     +-----------+------------+                                       │
│     |                        |                                       │
│ SABnzbd (usenet, prio 1)  qBittorrent (torrents, prio 2,             │
│                            tunneled via Gluetun/PIA)                 │
│     +-----------+------------+                                       │
│                 v                                                    │
│  /mnt/media/downloads/complete  (post-processed staging)             │
│                 |                                                    │
│     Radarr/Sonarr import -->  movies/   tv/                          │
│                 |                                                    │
│  FileFlows watch folder --> in-place transcode                       │
│   bitrate >20Mbps: remux MKV --> HEVC VAAPI --> cap 20Mbps           │
│   (CPU fallback on VAAPI failure) --> replace original               │
│                 |                                                    │
│  Jellyfin library scan --> streams via tunnel                        │
│                                                                      │
│Internal NVMe -- /home/skim/jellyfin-configs/                         │
│  all app configs, databases, cache, metadata                         │
│                                                                      │
│Cloudflare Tunnel --> suvannmedia.com (outbound-only)                 │
│  jellyfin.suvannmedia.com       OPEN (mobile apps)                   │
│  jellyseerr.suvannmedia.com     OPEN (family)                        │
│  sabnzbd / prowlarr / radarr / sonarr / bazarr /                     │
│  fileflows / qbittorrent .suvannmedia.com                            │
│    Access gate: NOT ENFORCED (app auth only)                         │
└──────────────────────────────────────────────────────────────────────┘
```

## Services

| Service    | Port  | Image                                   | Mounts to                    | External                     | Auth             |
|------------|-------|-----------------------------------------|------------------------------|------------------------------|------------------|
| Jellyfin   | 8096  | `docker.io/jellyfin/jellyfin:latest`    | `/config`                    | jellyfin.suvannmedia.com     | Open (Jellyfin)  |
| Jellyseerr | 5055  | `fallenbagel/jellyseerr:latest`         | **`/app/config`** ⚠️         | jellyseerr.suvannmedia.com   | Open (Jellyfin)  |
| SABnzbd    | 8085  | `linuxserver/sabnzbd:latest`            | `/config`                    | sabnzbd.suvannmedia.com      | Access gate*       |
| Prowlarr   | 9696  | `linuxserver/prowlarr:latest`           | `/config`                    | prowlarr.suvannmedia.com     | Access gate*       |
| Radarr     | 7878  | `linuxserver/radarr:latest`             | `/config`                    | radarr.suvannmedia.com       | Access gate*       |
| Sonarr     | 8989  | `linuxserver/sonarr:latest`             | `/config`                    | sonarr.suvannmedia.com       | Access gate*       |
| Bazarr     | 6767  | `linuxserver/bazarr:latest`             | `/config`                    | bazarr.suvannmedia.com       | Access gate*       |
| FileFlows  | 5000  | `localhost/fileflows-amd-vaapi:latest`  | `/app/Data`                  | fileflows.suvannmedia.com    | Access gate*       |
| qBittorrent| 8090  | `linuxserver/qbittorrent:latest`         | `/config`, `/downloads`      | qbittorrent.suvannmedia.com  | Access* + qBit   |

> **\* Access gate:** intended Cloudflare Access protection is currently NOT
> enforced (see Cloudflare Access section). App-level auth is all that stands
> between these URLs and the internet right now.
>
> **Jellyseerr gotcha:** Jellyseerr expects its config mounted at **`/app/config`**,
> NOT `/config`. Mounting to the wrong path causes the first-boot setup wizard to
> loop. The correct unit mount is
> `-v /home/skim/jellyfin-configs/jellyseerr:/app/config`.

> Most services use `--network host`. qBittorrent is the deliberate exception:
> it shares Gluetun's network namespace, and Gluetun publishes WebUI port 8090
> on loopback. This fail-closed design prevents qBittorrent from bypassing PIA.
> All run as `User=1000:1000` (container UID is `1000:1000`).
> FileFlows additionally runs as **`User=skim`** at the systemd level so podman
> can access the locally-built `localhost/` image.

## Disk Layout

| Storage | Mount/path | Purpose |
|---------|------------|---------|
| Internal NVMe | `/home/skim/jellyfin-configs` | App configs, databases, cache, metadata |
| 5.5T USB drive (SSI H/W RAID5 controller) | `/mnt/media` (ext4, single volume) | Movies, TV, downloads, FileFlows work |

### Configs on internal NVMe

All application state lives at `/home/skim/jellyfin-configs/` (canonical
Bazzite path: `/var/home/skim/jellyfin-configs/`). This prevents a USB
enclosure disconnect from taking every application database down with it.

Rootful Podman containers need both path traversal and a persistent SELinux
container label:

```bash
sudo chmod 711 /home/skim
sudo semanage fcontext -a -t container_file_t \
  '/var/home/skim/jellyfin-configs(/.*)?'
sudo restorecon -RF /var/home/skim/jellyfin-configs
```

Do not put Jellyfin or Arr SQLite databases back on mergerfs. The old
`var-mnt-jellyfin.mount` unit is retained only as migration history and is not
a dependency of the current services.

### Media storage (mergerfs pool retired Sept 2026)

`/mnt/media` is currently a **single 5.5T ext4 volume** (ext4 on an SSI
hardware-RAID5 USB enclosure, presented as /dev/sda) mounted directly. The
three-drive mergerfs pool described in older revisions of this README no
longer exists on the running system:

- `mergerfs.service` is installed but **inactive**; `var-mnt-pool{1,2,3}.mount`
  and `mnt-pool{1,2,3}.mount` units are **masked** (their old drive UUIDs no
  longer exist).
- `/usr/local/bin/mergerfs` (2.42.0) is still installed. To rebuild a pool:
  unmask the pool mounts, recreate them for the new drive UUIDs, and restore
  the `mergerfs.service` ExecStart from `systemd/mergerfs.service`.

**Backup caveat:** the enclosure's H/W RAID5 gives single-drive failure
tolerance only. There is currently no off-device copy of the library; the
enclosure, its USB bridge, or the controller is a single point of failure.
RAID is not a backup.

## Prerequisites

Before you start, you'll need:

1. **Hardware** — USB media drive(s), internal NVMe for application state
2. **Domain** — registered at Cloudflare ($8–12/yr)
3. **Usenet provider** — Frugal Usenet (~$5/mo)
4. **VPN provider** — Private Internet Access (torrent fallback)
5. **Indexer** — NZBGeek (~$10/yr)
6. **TMDb API key** — free from themoviedb.org

## Quick rebuild (fresh Bazzite install)

```bash
# 1. Install git + podman (dnf is stock on Bazzite)
sudo dnf install -y git podman
git clone https://github.com/ra535i/JellyFin.git /opt/jellyfin
cd /opt/jellyfin

# 2. Prepare local application state with persistent SELinux labels
mkdir -p /home/skim/jellyfin-configs
sudo chmod 711 /home/skim
sudo semanage fcontext -a -t container_file_t \
  '/var/home/skim/jellyfin-configs(/.*)?'
sudo restorecon -RF /var/home/skim/jellyfin-configs

# 3. (Only if pooling multiple drives) Install mergerfs (static binary,
#    no rpm-ostree layer). Current build is a single volume; skip this.
sudo bash install/install_mergerfs.sh

# 4. Build the custom FileFlows image (needs ffmpeg + VAAPI)
podman run -d --name ff-builder docker.io/revenz/fileflows:latest
podman exec -u 0 ff-builder apt update && apt install -y \
  ffmpeg vainfo mesa-va-drivers intel-media-va-driver-non-free
podman commit ff-builder localhost/fileflows-amd-vaapi:latest
podman rm -f ff-builder

# 5. Install the full stack (Jellyfin + Arr + FileFlows)
sudo bash install/setup.sh

# 6. Optional torrent fallback through PIA
# Follow torrent/README.md after creating torrent/.env from .env.example.
```

Existing configs under `/home/skim/jellyfin-configs/` are preserved — all apps
come back with their same settings, users, libraries, and API keys.

## First-time setup (from scratch, no configs)

If `/home/skim/jellyfin-configs/` is empty (truly fresh build).

### Step 1: Apply SABnzbd tunnel fix

SABnzbd blocks external access by default. Since it's behind Cloudflare Tunnel,
the requests appear to come from Cloudflare's IPs. Edit the config:

```ini
# /home/skim/jellyfin-configs/sabnzbd/sabnzbd.ini
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

> **⚠ CURRENT STATUS (verified 2026-09-05):** Access enforcement is NOT
> active (remedial operation pending after the Aug 2026 incident). The admin
> URLs currently 302 to the apps' own login pages, not to Cloudflare Access.
> Re-enabling Access is the highest-priority security item for this stack.

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

System service files live in `systemd/` and are deployed to
`/etc/systemd/system/`. FileFlows is an exception: it runs as a **user**
unit, symlinked from this repo at `~/.config/systemd/user/fileflows.service`,
enabled with `loginctl enable-linger skim`. No system-level FileFlows unit
exists (removed Aug 2026) — only one podman container can own the name and
port 5000.

Gluetun and qBittorrent are also user units, sourced from `torrent/` and
installed into `~/.config/systemd/user/`. Their credentials remain only in
gitignored `torrent/.env`. See `torrent/README.md` and run
`torrent/verify-torrent-stack.sh` after deployment.

| File | Purpose |
|------|---------|
| `var-mnt-jellyfin.mount` | Legacy external config-drive unit (not used by current services) |
| `mergerfs.service` | mergerfs pool unit (RETIRED Sept 2026 — inactive; single volume in use) |
| `jellyfin.service` | Jellyfin media server |
| `jellyseerr.service` | Jellyseerr request portal (**mounts to `/app/config`**) |
| `sabnzbd.service` | SABnzbd usenet downloader |
| `prowlarr.service` | Prowlarr indexer manager |
| `radarr.service` | Radarr movie automation |
| `sonarr.service` | Sonarr TV automation |
| `bazarr.service` | Bazarr subtitle automation |
| `fileflows.service` | FileFlows media processing (installed as a **user unit**) |
| `cloudflared.service` | Cloudflare Tunnel (system-level, not user-level) |
| `torrent/gluetun.service` | PIA OpenVPN tunnel, kill switch, port forwarding (user unit) |
| `torrent/qbittorrent.service` | Torrent client sharing Gluetun's network namespace (user unit) |

### Key systemd quirks

- **FileFlows** has `TimeoutStartSec=90` — plenty now that ffmpeg and VAAPI
  drivers are baked into the committed image (no apt install at boot).
- **FileFlows** runs as `User=skim` (not root) so `podman` can access the
  `localhost/fileflows-amd-vaapi:latest` image (local images owned by the user).
- **Only the FileFlows user unit may be enabled.** Disable the obsolete system
  unit with `sudo systemctl disable --now fileflows.service`; manage the working
  one with `systemctl --user ...`.
- **FileFlows** cleans up with `ExecStartPre=-/usr/bin/podman rm -f fileflows`
  plus `ExecStop=/usr/bin/podman stop -t 30 fileflows` instead of `--rm`,
  because `User=skim` mode makes podman stop/rm tricky in the restart cycle.
- **The abort.conf drop-in** (`/etc/systemd/system/service.d/10-timeout-abort.conf`)
  sets `TimeoutStopFailureMode=abort`, which sends SIGABRT to any service that
  fails to stop in time. This can cause surprising coredumps. To disable:
  ```bash
  sudo mkdir -p /etc/systemd/system/service.d
  sudo ln -sv /dev/null /etc/systemd/system/service.d/10-timeout-abort.conf
  ```
- **Power blips** require `systemctl reset-failed <service>` before a service
  that hit its restart limit will try again.
- **Gluetun + qBittorrent** use user-systemd with linger. qBittorrent has
  `BindsTo=gluetun.service`, so stopping/restarting Gluetun also stops qBit;
  qBit cannot remain running on a stale or non-VPN network namespace.

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
-v /home/skim/jellyfin-configs/jellyseerr:/app/config
```

### FileFlows custom image
The `fileflows-amd-vaapi:latest` image is built on top of the stock
`revenz/fileflows` by installing ffmpeg and VAAPI drivers, then committed —
so the packages are baked into the image and there's no apt install at boot.
Rebuild it after pulling a new upstream (see `scripts/media-stack-updater.sh`).

### FileFlows User=skim
FileFlows runs with `User=skim` at the systemd level (not root). This is
necessary because `podman run` as root can't see locally-built images in the
`localhost/` namespace — those are user-scoped. The tradeoff is that `--rm`
doesn't work as reliably for cleanup, so `ExecStartPre` + `ExecStop` handle
container removal explicitly.

### FileFlows PUID/PGID breakage
Do NOT set `PUID=1000`/`PGID=1000` in the FileFlows unit. Under rootless
podman, container uid 0 already maps to host `skim` (1000); with PUID unset
the entrypoint's dotnet process writes to /mnt/media as skim and can replace
transcoded files. Setting `PUID=1000` makes the app run as *container* uid
1000, which maps to an unmapped subuid on the host — every media write fails
with EACCES. See the note in `systemd/fileflows.service`.

### Power blip recovery
After a sudden power loss, a service that exhausted its restart limit may need
its failure counter reset. Recovery:

```bash
systemctl --user reset-failed fileflows
systemctl --user restart fileflows
sudo systemctl reset-failed
sudo systemctl --failed
```

### Cloudflare tunnel user→system migration
The tunnel originally ran as a user-level systemd service (via `systemctl
--user` with lingering). It was migrated to a system-level service because
user services sometimes fail to start at boot, leaving the server inaccessible
after a power outage. The binary was copied from `~/.local/bin/cloudflared` to
`/usr/local/bin/cloudflared` for system-level execution.
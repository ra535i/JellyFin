# Media Server — Bazzite

Jellyfin + usability stack on Bazzite (immutable Fedora). All services run as
systemd-managed podman containers. Survives reboots, survives OS updates.

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
└──────────────────────────────────────────────────────────────┘
```

## Services

| Service    | Port  | Purpose                     |
|------------|-------|-----------------------------|
| Jellyfin   | 8096  | Media streaming             |
| SABnzbd    | 8080  | Usenet downloader           |
| Prowlarr   | 9696  | Indexer management          |
| Radarr     | 7878  | Movie automation            |
| Sonarr     | 8989  | TV automation               |
| Bazarr     | 6767  | Subtitle automation         |
| Jellyseerr | 5055  | Family request portal       |

## First-time setup (new machine)

On a fresh Bazzite install, one-time prep:

```bash
# 1. Mount the drives (edit /etc/fstab with UUIDs from blkid)
sudo mkdir -p /mnt/pool1 /mnt/pool2 /mnt/pool3 /mnt/jellyfin
# Add fstab entries like:
# UUID=fe62eb62... /mnt/pool1 ext4 defaults,nofail 0 2
# ... etc
sudo mount -a

# 2. Run the full setup
sudo bash install/install_mergerfs.sh
sudo bash install/setup.sh
```

## Rebuild from scratch (everything blown away)

```bash
# 1. Clone the repo on a fresh machine
git clone <your-repo-url> media-server
cd media-server

# 2. Mount drives (see "First-time setup" above)
#    (assumes drives are still partitioned/formatted with the same UUIDs)

# 3. Install everything
sudo bash install/install_mergerfs.sh
sudo bash install/setup.sh
```

## Usenet accounts

Before the stack works, you need:

1. **Usenet provider** (recommended: Eweka ~€6/mo)
   - Sign up at https://www.eweka.nl
   - Get your server hostname, username, password
   - Input into SABnzbd (`http://[ip]:8080`) → Config → Servers

2. **Indexer** (recommended: NZBGeek ~$10/yr)
   - Sign up at https://nzbgeek.info
   - Get your API key
   - Add to Prowlarr (`http://[ip]:9696`) → Indexers → Add NZBGeek

## Stack wiring (after setup)

After the initial config of each app, wire them together:

**SABnzbd** → Config → General → Enable API key (copy it)
**Prowlarr** → Settings → Apps → Add Radarr + Sonarr + SABnzbd
**Radarr** → Settings → Download Client → Add SABnzbd (paste API key)
**Radarr** → Settings → Indexers → Add Prowlarr
**Radarr** → Settings → Media Management → Root folder → `/movies`
**Sonarr** → Same as Radarr but root folder → `/tv`
**Jellyseerr** → Settings → Jellyfin → Connect (Jellyfin URL, API key)
**Jellyseerr** → Settings → Radarr/Sonarr → Connect
**Bazarr** → Settings → Radarr/Sonarr → Connect
**Bazarr** → Subtitles → Provider → Add proxy/subtitle sources

## Migrating from a disaster

If the whole machine needs to be rebuilt:

1. Reinstall Bazzite
2. `git clone <repo>`  
3. Mount drives (they're still partitioned/formatted, just mount via fstab)
4. `sudo bash install/install_mergerfs.sh`
5. `sudo bash install/setup.sh`
6. All app configs are on `/mnt/jellyfin/config/` — they survive the rebuild
7. Jellyfin, Radarr, Sonarr, etc. will come back with their same configs
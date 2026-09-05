This directory contains everything needed to rebuild the entire media server
stack from a fresh Bazzite install.

See README.md in this directory for instructions.

Contents:
  - install/setup.sh             Master installer (run this)
  - install/install_mergerfs.sh  Downloads + installs mergerfs
  - install/install_jellyfin.sh  Jellyfin container + systemd service
  - install/install_arr_stack.sh SABnzbd, Prowlarr, Radarr, Sonarr, Bazarr, Jellyseerr, FileFlows
  - systemd/*.service            All systemd service files
  - systemd/var-mnt-jellyfin.mount  Legacy external config-drive unit (not in use)
  - cloudflare/cloudflared.service  Cloudflare Tunnel service
  - cloudflare/config.yml.template  Tunnel config template
  - cloudflare/install_tunnel.sh    Deploys tunnel + DNS records
  - cloudflare/setup_access.sh      Creates Cloudflare Access gates
  - fileflows/flows/*.json          FileFlows pipeline templates
  - fileflows/import_flows.sh       Flow importer
  - scripts/sab_rename_absolute_episodes.py  SABnzbd absolute-episode rename utility
  - scripts/media-stack-updater.sh           Weekly image + cloudflared updater (cron)
  - scripts/fix-media-permissions.sh         Permissions watchdog for /mnt/media

NOTE: Torrent support (Gluetun + qBittorrent) was removed Aug 2026 and
RESTORED Aug 31 2026 (commit 3fd35e6) as a PIA-tunneled priority-2 download
client. Both user units are active on the running system; Radarr and Sonarr
have qBittorrent enabled alongside SABnzbd. See torrent/README.md and
torrent/verify-torrent-stack.sh.

MEDIA STORAGE NOTE (Sept 2026): /mnt/media is a single 5.5T ext4 volume on a
H/W-RAID5 USB enclosure. The 3-drive mergerfs pool is retired
(mergerfs.service inactive, pool mounts masked).
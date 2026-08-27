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

NOTE: Torrent support (Gluetun + qBittorrent) was removed Aug 2026.
Usenet-only via SABnzbd. See git history for the old gluetun/qbittorrent
service files if needed.
#!/usr/bin/env bash
set -euo pipefail

host_ip=$(curl -fsS --max-time 10 https://api.ipify.org)
vpn_ip=$(podman exec gluetun wget -qO- --timeout=10 https://api.ipify.org)
qb_ip=$(podman exec qbittorrent curl -fsS --max-time 10 https://api.ipify.org)
forwarded_port=$(cat "$HOME/jellyfin-configs/gluetun/forwarded_port")
local_http=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:8090/)

printf 'gluetun=%s enabled=%s\n' \
  "$(systemctl --user is-active gluetun.service)" \
  "$(systemctl --user is-enabled gluetun.service)"
printf 'qbittorrent=%s enabled=%s\n' \
  "$(systemctl --user is-active qbittorrent.service)" \
  "$(systemctl --user is-enabled qbittorrent.service)"
printf 'host_ip=%s vpn_ip=%s qb_ip=%s\n' "$host_ip" "$vpn_ip" "$qb_ip"
printf 'forwarded_port=%s local_http=%s\n' "$forwarded_port" "$local_http"

[[ "$vpn_ip" != "$host_ip" ]]
[[ "$qb_ip" == "$vpn_ip" ]]
[[ "$local_http" == 200 ]]
[[ "$(podman inspect qbittorrent --format '{{.HostConfig.NetworkMode}}')" == container:* ]]
[[ "$(podman exec gluetun wget -qO- --timeout=15 \
  "https://portcheck.transmissionbt.com/$forwarded_port")" == 1 ]]
podman exec -u 1000:1000 qbittorrent /bin/sh -c \
  'touch /downloads/torrents/.verify-write && rm /downloads/torrents/.verify-write'

echo 'PASS: qBittorrent is serving locally, writable, port-forwarded, and egressing through PIA.'
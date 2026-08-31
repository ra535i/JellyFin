# PIA + Gluetun + qBittorrent

This stack runs rootless under the `skim` user. qBittorrent shares Gluetun's network namespace, so it has no independent route to the host WAN. Gluetun's firewall remains enabled as the kill switch.

## Architecture

- Gluetun: PIA OpenVPN, PIA native port forwarding, firewall enabled
- qBittorrent: `--network container:gluetun`
- Local WebUI origin: `http://127.0.0.1:8090` (published by Gluetun)
- Download mount: host `/mnt/media/downloads` = container `/downloads`
- Torrent save path: `/downloads/torrents`
- Incomplete path: `/downloads/torrents/incomplete`
- Cloudflare hostname: `qbittorrent.suvannmedia.com` -> `http://localhost:8090`

## Credentials

Copy `.env.example` to `.env`, fill in the PIA OpenVPN credentials and qBittorrent WebUI credentials, then `chmod 600 .env`. `.env` is gitignored.

## Install

```bash
mkdir -p /mnt/media/downloads/torrents/incomplete
# Rootless qBittorrent's internal UID 1000 maps to host UID 525287.
# Preserve normal skim ownership while granting qBittorrent durable write access.
podman unshare setfacl -R -m u:1000:rwx /mnt/media/downloads/torrents
podman unshare setfacl -R -d -m u:1000:rwx /mnt/media/downloads/torrents

mkdir -p ~/.config/systemd/user
install -m 0644 torrent/gluetun.service torrent/qbittorrent.service ~/.config/systemd/user/
chmod 700 torrent/update-qbittorrent-port.sh
systemctl --user daemon-reload
systemctl --user enable --now gluetun.service qbittorrent.service
```

User linger must be enabled so the stack starts at boot (`loginctl show-user skim -p Linger`).

## Required qBittorrent settings

The WebUI needs a permanent password and `bypass_local_auth=true`; the latter permits Gluetun's localhost-only port-forward hook. The external WebUI remains protected by qBittorrent authentication plus Cloudflare Access.

Sonarr and Radarr should connect to `127.0.0.1:8090`, use their own categories
(`tv-sonarr` and `radarr`), and keep qBittorrent at priority 2. SABnzbd remains
priority 1 and each default delay profile keeps `preferredProtocol=usenet`, so
torrents are the fallback rather than replacing Usenet.

## Verification

Never trust service state alone. Verify all boundaries:

1. `systemctl --user is-active gluetun qbittorrent`
2. Gluetun logs show a PIA public IP and a forwarded port.
3. qBittorrent's log reports the same PIA IP, never the host ISP IP.
4. qBittorrent preferences show `current_network_interface=tun0` and `listen_port` equal to `/home/skim/jellyfin-configs/gluetun/forwarded_port`.
5. `curl http://127.0.0.1:8090/` returns the qBittorrent WebUI.
6. `https://qbittorrent.suvannmedia.com` redirects to Cloudflare Access and reaches qBittorrent after authentication.
7. Stopping Gluetun also stops qBittorrent; qBittorrent must not continue independently.

For the non-destructive checks above, run:

```bash
./torrent/verify-torrent-stack.sh
```

The ACL commands are required on this rootless Podman host. A plain host-side
`chmod 775` is insufficient because container UID 1000 maps to host UID 525287.

PIA's forwarded port normally remains stable for roughly 60 days because `/gluetun` is persistent. Gluetun refreshes it and reruns the qBittorrent update hook.

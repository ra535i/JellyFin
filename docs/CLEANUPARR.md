# Cleanuparr — queue-monitor operations and recovery

Cleanuparr is the stack's Arr/qBittorrent queue monitor. It runs as the rootful
`cleanuparr.service` Podman unit, stores its persistent state on NVMe at
`/home/skim/jellyfin-configs/cleanuparr`, and listens locally on port `11011`.
Its public route is `https://cleanuparr.suvannmedia.com`, protected by a
dedicated Cloudflare Access application. Cloudflare Access protects the public
hostname only; it does not secure direct LAN access to port `11011`.

## Service and data

- Unit source: `systemd/cleanuparr.service`
- Container image: pinned by immutable digest in that unit and
  `scripts/media-stack-updater.sh`
- Persistent data: `/home/skim/jellyfin-configs/cleanuparr`
- SQLite database: `/home/skim/jellyfin-configs/cleanuparr/cleanuparr.db`
- Automatic pre-change backups: `/home/skim/jellyfin-configs/cleanuparr/backups/`
- Health endpoint: `http://127.0.0.1:11011/health/ready`

Treat the persistent directory and its backups as sensitive: they contain app
configuration and credentials. They are excluded from git.

## Approved production policy

This policy exists to monitor recurring stuck qBittorrent downloads without
risking private-torrent ratios or deleting library media.

- **Dry Run is enabled.** Actions are logged but not performed.
- Connectivity protection is enabled before queue decisions; HTTP timeout is
  30 seconds with three retries and a 72-hour strike-history window.
- Queue Cleaner runs every five minutes.
- Public stalled-download rule: 12 strikes (about one hour), with strike count
  reset when download progress resumes.
- Downloading-metadata rule: 12 strikes.
- Failed-import rule: six strikes, matching only clear import failures (such as
  title mismatches, unparsable releases, or missing/ineligible files).
- Failed imports ignore private torrents, skip entries absent from qBittorrent,
  do not force import, and do not change categories.

Do **not** enable private-torrent cleanup, orphan/download/source-file deletion,
malware cleanup, seeding cleanup, slow-download cleanup, category changes, or
forced imports without a separate review and dry-run evidence.

Cleanuparr does not monitor SABnzbd directly. SABnzbd stalls remain a manual
operational concern.

## Recovery and verification

1. Restore `/home/skim/jellyfin-configs/cleanuparr` with the wider NVMe
   application-state backup before starting the service.
2. Deploy the unit with `sudo bash install/setup.sh`, or install only this unit:

   ```bash
   sudo install -m 0644 systemd/cleanuparr.service /etc/systemd/system/cleanuparr.service
   sudo systemctl daemon-reload
   sudo systemctl enable --now cleanuparr.service
   ```

3. Verify both the unit and the actual HTTP readiness endpoint:

   ```bash
   sudo systemctl is-active cleanuparr.service
   curl --fail --max-time 8 http://127.0.0.1:11011/health/ready
   ```

4. Restore the tunnel route from `cloudflare/config.yml.template`, DNS through
   `cloudflare/install_tunnel.sh`, and its Cloudflare Access app through
   `cloudflare/setup_access.sh`. Verify an unauthenticated request redirects to
   Cloudflare Access:

   ```bash
   curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' \
     https://cleanuparr.suvannmedia.com/
   ```

5. If the configuration database was not restored, use the local UI to create
   the admin account and re-associate Sonarr, Radarr, and qBittorrent. Rebuild
   only the approved policy above, retaining Dry Run.

Never edit `cleanuparr.db` while Cleanuparr is running. Stop the service and
take a SQLite backup first if a deliberate configuration repair is needed.
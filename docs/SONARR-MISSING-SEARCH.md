# Sonarr missing-episode search batch

Sonarr's RSS sync notices newly posted releases. It does not periodically
perform historical searches for its existing Missing list, because doing so can
overload indexers. This systemd timer backfills that list in deliberately small
batches.

## Production policy

- Runs daily at 02:00 local time with up to 15 minutes of jitter.
- Queues one Sonarr `EpisodeSearch` command for **10 monitored missing
  episodes** per run.
- Uses a local cursor at
  `/home/skim/jellyfin-configs/sonarr-missing-search/cursor.json` to rotate
  through the missing list instead of repeatedly searching the same oldest
  episodes.
- Calls Sonarr locally and reads its API key from the existing config file; no
  credential is stored in the repository or in the unit.
- It does not search unmonitored episodes and it does not send anything directly
  to SABnzbd or qBittorrent. Sonarr still applies its quality profiles, release
  restrictions, indexer policy, and download-client priorities.

At ten episodes per day, the current 371-episode missing backlog takes roughly
five to six weeks to receive one historical-search attempt, without blasting
Prowlarr and its indexers in a single night.

## Install and verify

```bash
sudo install -m 0644 systemd/sonarr-missing-search.service /etc/systemd/system/
sudo install -m 0644 systemd/sonarr-missing-search.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now sonarr-missing-search.timer

# Validate selection only; this does not enqueue a Sonarr search.
sudo -u skim /home/skim/JellyFin/scripts/sonarr-missing-search.sh --dry-run
systemctl list-timers sonarr-missing-search.timer
```

The deployed unit executes the repository script. Install the unit files again
after changing their repository versions.

```bash
sudo -u skim /home/skim/JellyFin/scripts/sonarr-missing-search.sh
journalctl -u sonarr-missing-search.service --no-pager -n 30
```

Do not increase the batch size until Prowlarr/indexer logs show the existing
overnight rate is clean. Tokyo Toshokan has already returned temporary 429
throttles during interactive searching.
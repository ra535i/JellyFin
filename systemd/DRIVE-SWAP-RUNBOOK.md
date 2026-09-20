# DRIVE-SWAP RUNBOOK — Yottamaster greens → Reds (Reds ETA ~Sep 16-21, 2026)

> **Current recovery invariant (post-migration):** FileFlows media is on the
> RAID5 pool, but runner scratch is not. Preserve
> `/home/skim/jellyfin-configs/runner-temp:/temp` on NVMe. Do not recreate the
> retired `/var/mnt/pool1/fileflows-working:/temp` mount; RAID-backed runner
> scratch caused no-op files to spend minutes in plugin startup.

Goal: keep the whole suvannmedia stack live on backup paths while we restore to
the fresh RAID5. Path never moves (/var/mnt/media), so no service configs change.

Measured facts (Sep 11):
- kimshare SMB: real full-library sync did 118 GiB in 54 min = ~37 MB/s sustained (planning number)
- BUT kimshare throttles under long sessions: Silo test (47.8 GiB, 3 hrs) averaged only ~4.5 MB/s
- tv = 1.19 TiB → restore ≈ 10 hrs at planning rate; worst case much longer if NAS throttles
- Parallel jobs do NOT add throughput (28 MB/s combined in test). Run ONE job, monitor it.
- If restore stalls below ~10 MB/s for >15 min: kill + restart rclone (fresh SMB session often un-throttles)
- FileFlows runner scratch stays on NVMe; only media is restored to the new array

## PRE-SWAP (do once backups verified green — expected done Sep 11-12)
[ ] rclone check both legs:
      rclone check /var/mnt/media/tv/ mycloud:/Public/tv --one-way -v          # DONE Sep 11: 0 differences, 2679 files
      rclone check /var/mnt/media/movies/ /run/media/system/internal-2/movies/ --one-way -v   # HUNG 2.4h in D-state on Yottamaster USB bridge; killed. VERIFIED INSTEAD via byte-exact du: both sides = 757,771,657,584 bytes, 506 files each
      rclone check /var/mnt/media/fileflows-working/ ... --one-way -v          # SKIP pre-swap (live dir); do pause+delta at swap time

⚠️ WARNING SIGN: the Yottamaster USB bridge hung a process in uninterruptible D-state for 2.4h on Sep 11
   while reading the green drives. If this recurs, suspect the JMicron bridge or a failing green drive —
   report to Seth before physical swap (may need to pull drives one at a time and test).
[ ] Smoke-test FUSE playback NOW (before swap day):
      sudo sed -i 's/^# user_allow_other/user_allow_other/' /etc/fuse.conf   # needs password
      rclone mount mycloud:/Public/tv/Silo /home/skim/.fuse-label-test --vfs-cache-mode writes --allow-other &
      ls -Z /home/skim/.fuse-label-test/    # labels visible? readable as skim?
      fusermount -u /home/skim/.fuse-label-test

## SWAP DAY — Phase 1: repoint to backups (~30 min hands-on)
[ ] 1. sudo sed -i 's/^# user_allow_other/user_allow_other/' /etc/fuse.conf   (if not done pre-swap)
[ ] 2. Relabel the temp tree so containers can read it (one-time, ~5-10 min):
      sudo chown -R skim:skim /home/skim/.tmp-media
      sudo restorecon -RFv /home/skim/.tmp-media   # or: sudo semanage fcontext -a -t container_file_t '/home/skim/\.tmp-media(/.*)?' && sudo restorecon -RFv /home/skim/.tmp-media
[ ] 3. Enable + start temp units (I have passwordless systemctl/mount):
      sudo cp /home/skim/JellyFin/systemd/{tmp-media.mount,mnt-tmp-media-movies.mount,mnt-tmp-media-fileflows-working.mount,var-mnt-media-tv-rclone.service} /etc/systemd/system/
      sudo systemctl daemon-reload
      sudo systemctl enable --now mnt-tmp-media-movies.mount mnt-tmp-media-fileflows-working.mount var-mnt-media-tv-rclone.service tmp-media.mount
[ ] 4. Verify merged tree: ls /var/mnt/media → movies tv fileflows-working downloads all present
[ ] 5. Smoke-test Jellyfin direct-play of a TV show (off FUSE) + one movie (off NVMe). Fix labels if EACCES.
[ ] 6. Restart dependents only if needed: sudo systemctl restart jellyfin sonarr radarr sabnzbd bazarr fileflows

## SWAP DAY — Phase 2: physical swap + restore
[ ] Pull 3 greens, drop in 3 Reds, set RAID mode switches on back (ONLY the switches we're changing), init fresh array
[ ] mkfs ext4 x3 → LVM/RAID per existing setup → mount as /var/mnt/media source (fstab entries already there, commented)
[ ] Start restores (I run these + report hourly):
      rclone copy mycloud:/Public/tv/ <new-array>/tv/ --transfers 8 --checkers 16        # ~10 hrs, overnight
      cp -a /run/media/system/internal-2/movies/. <new-array>/movies/                     # parallel
      cp -a /run/media/system/internal-2/fileflows-working/. <new-array>/fileflows-working/
[ ] qBit: state (BT_backup) lives on NVMe config drive — untouched. Re-download the 290 GB of torrents later; empty downloads/ bind keeps SAB/qBit alive meanwhile.

## SWAP DAY+1 — Phase 3: swap back (~15 min)
[ ] Uncomment fstab entries for real drives, remount pool1/2/3 to fresh ext4s
[ ] sudo systemctl stop tmp-media.mount mnt-tmp-media-movies.mount mnt-tmp-media-fileflows-working.mount var-mnt-media-tv-rclone.service
[ ] Restart mergerfs + services; verify Jellyfin + Arrs see libraries on real array
[ ] rclone check new-array vs backups (final verification)

## KEEP BACKUPS through first week of normal use. Then:
[ ] Delete MyCloud tv/ (1.19 TiB), wipe NVMe backup dirs when confident.

# pool1 self-heal

This is a bounded, read-only-first recovery path for the five-disk USB RAID5
enclosure. It never uses `mdadm --create`, `--add`, `--build`,
`--zero-superblock`, or a forced assemble. Only after every member passes its
superblock consistency checks may it reset the JMicron USB bridge, stop pool
writers, replace stale kernel md state, assemble and mount the pool read-write,
probe a real media file, and restart the writer stack. It refuses to proceed
when any member cannot be proven clean and mutually consistent.

Install once from a local terminal while direct access is available:

```bash
sudo install -o root -g root -m 0755 \
  /home/skim/JellyFin/scripts/pool1-selfheal.sh \
  /usr/local/sbin/pool1-selfheal
sudo install -o root -g root -m 0644 \
  /home/skim/JellyFin/systemd/pool1-selfheal.service \
  /etc/systemd/system/pool1-selfheal.service
sudo install -o root -g root -m 0644 \
  /home/skim/JellyFin/systemd/pool1-selfheal.timer \
  /etc/systemd/system/pool1-selfheal.timer
sudo install -o root -g root -m 0440 \
  /home/skim/JellyFin/systemd/90-pool1-selfheal.sudoers \
  /etc/sudoers.d/90-pool1-selfheal
sudo visudo -cf /etc/sudoers.d/90-pool1-selfheal
sudo systemctl daemon-reload
sudo systemctl enable --now pool1-selfheal.timer
sudo -n /usr/local/sbin/pool1-selfheal --status
```

After installation, Hermes can invoke only these two exact root commands without
asking for a password:

```bash
sudo -n /usr/local/sbin/pool1-selfheal --status
sudo -n /usr/local/sbin/pool1-selfheal --recover-rw
```

The timer is the primary recovery mechanism and does not depend on Hermes or
Telegram being online. When `/dev/md0` is already complete and pool1 is mounted
read-write it exits without changing anything. Telegram recovery is the manual
remote fallback.
A physically dead or unpowered enclosure still requires hardware intervention;
`usbreset` can reset a present USB bridge but cannot energize a dead port.

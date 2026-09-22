#!/bin/bash
# fix-media-permissions.sh — Watchdog that ensures FileFlows can read/write media.
# Runs silently unless it actually changes something.
#
# WHAT IT FIXES:
#   1. Directories under /var/mnt/pool1/ — ensures owner/group write access and
#      removes world-write access so FileFlows can replace files safely.
#   2. .mkv / .mp4 files — ensures owner/group read-write and world-read access.
#
# EXIT CODES:
#   0 = nothing changed (no output)
#   1 = permissions were fixed (prints what changed)

set -euo pipefail
MEDIA_BASE="/var/mnt/pool1"
CHANGED=0

# 1. Fix directories — FileFlows needs traversal and write access, but never
# grant world-write access to the media tree.
while IFS= read -r -d '' dir; do
  current=$(stat -c '%a' "$dir" 2>/dev/null || echo "0")
  chmod u+rwx,g+rwx,o+rx,o-w "$dir"
  updated=$(stat -c '%a' "$dir" 2>/dev/null || echo "0")
  if [ "$current" != "$updated" ]; then
    echo "  🔧 $dir (was $current → $updated)"
    CHANGED=1
  fi
done < <(find "$MEDIA_BASE" -type d -not -path '*/\.*' -not -name '.stversions' -not -name '@eaDir' -print0 2>/dev/null)

# 2. Fix video files — owner/group can read and replace; everyone else can
# read for the media services, but nobody else can write.
while IFS= read -r -d '' file; do
  current=$(stat -c '%a' "$file" 2>/dev/null || echo "0")
  chmod u+rw,g+rw,o+r,o-w "$file"
  updated=$(stat -c '%a' "$file" 2>/dev/null || echo "0")
  if [ "$current" != "$updated" ]; then
    echo "  🔧 $(basename "$file") (was $current → $updated)"
    CHANGED=1
  fi
done < <(find "$MEDIA_BASE" -type f \( -name "*.mkv" -o -name "*.mp4" \) -not -path '*/\.*' -print0 2>/dev/null)

# Exit: 0 if nothing changed (silent), 1 if something was fixed
exit "$CHANGED"
#!/bin/bash
# fix-media-permissions.sh — Watchdog that ensures FileFlows can read/write media.
# Runs silently unless it actually changes something.
#
# WHAT IT FIXES:
#   1. Directories under /mnt/media/ — ensures 777 so FileFlows (UID 525287) can delete/replace files
#   2. .mkv / .mp4 files — ensures 664 (readable by everyone)
#
# EXIT CODES:
#   0 = nothing changed (no output)
#   1 = permissions were fixed (prints what changed)

set -euo pipefail
MEDIA_BASE="/var/mnt/media"
CHANGED=0

# 1. Fix directories — must be at least 755, but we set 777 for FileFlows
while IFS= read -r -d '' dir; do
  current=$(stat -c '%a' "$dir" 2>/dev/null || echo "0")
  if [ "$current" != "777" ] && [ "$current" != "775" ] && [[ "$current" != "7"[0-5][0-9] ]]; then
    chmod 777 "$dir"
    echo "  🔧 $dir (was $current → 777)"
    CHANGED=1
  fi
done < <(find "$MEDIA_BASE" -type d -not -path '*/\.*' -not -name '.stversions' -not -name '@eaDir' -print0 2>/dev/null)

# 2. Fix video files — ensure world-readable (at least 644)
while IFS= read -r -d '' file; do
  current=$(stat -c '%a' "$file" 2>/dev/null || echo "0")
  # Check if it's readable by others
  if [ ! -r "$file" ]; then
    chmod 644 "$file"
    echo "  🔧 $(basename "$file") (was $current → 644)"
    CHANGED=1
  elif [ "$current" != "644" ] && [ "$current" != "664" ] && [ "$current" != "666" ]; then
    # Fix only if perms are truly broken (not just non-standard)
    # Only change if group/other can't read
    perm_other_r=$(stat -c '%A' "$file" | cut -c8)
    if [ "$perm_other_r" != "r" ]; then
      chmod 644 "$file"
      echo "  🔧 $(basename "$file") (was $current → 644)"
      CHANGED=1
    fi
  fi
done < <(find "$MEDIA_BASE" -type f \( -name "*.mkv" -o -name "*.mp4" \) -not -path '*/\.*' -print0 2>/dev/null)

# Exit: 0 if nothing changed (silent), 1 if something was fixed
exit "$CHANGED"
#!/bin/bash
# remux-backup-watchdog.sh — self-cleanup for /var/mnt/media/remux-backup
#
# History: Aug 16-17, an agent session moved 12 REMUX originals (~800GB) into
# this folder as a one-off backup before re-downloading WEB-DLs. It was never
# cleaned up and sat there for 7 days until manually nuked on Aug 24. Nothing
# in the stack (FileFlows/Radarr/SAB/cron) references it — if it exists, it's
# a stale backup that should die.
#
# Behavior:
#   - No folder            -> silent (exit 0, no output)
#   - Folder <24h old      -> silent (grace period; may be an in-progress op)
#   - Folder >=24h old     -> log contents+size to audit file, delete, ALERT
#
# Exit codes: 0 = clean/silent, 1 = cleanup performed (alert), 99 = error

set -uo pipefail

MEDIA_ROOT=/var/mnt/media
TARGET="$MEDIA_ROOT/remux-backup"
AUDIT_LOG="$HOME/.hermes/profiles/last/scripts/logs/remux-backup-watchdog.log"
GRACE_HOURS=24

mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true

# ─── Not there: silent success ──────────────────────────────────────────────
if [ ! -d "$TARGET" ]; then
    exit 0
fi

# ─── Grace period: recently modified, leave it alone ────────────────────────
MTIME_EPOCH=$(stat -c %Y "$TARGET" 2>/dev/null || echo 0)
NOW_EPOCH=$(date +%s)
AGE_HOURS=$(( (NOW_EPOCH - MTIME_EPOCH) / 3600 ))

if [ "$AGE_HOURS" -lt "$GRACE_HOURS" ]; then
    exit 0   # too fresh — possibly an in-progress backup operation
fi

# ─── Stale: capture evidence, delete, alert ─────────────────────────────────
SIZE=$(du -sh "$TARGET" 2>/dev/null | cut -f1)
FILECOUNT=$(find "$TARGET" -type f 2>/dev/null | wc -l)
TOP_DIRS=$(du -sh "$TARGET"/*/ 2>/dev/null | sort -rh | head -10)

{
    echo "════ $(date '+%Y-%m-%d %H:%M') — AUTO-CLEANUP ════"
    echo "Target: $TARGET (age ${AGE_HOURS}h, size ${SIZE}, files ${FILECOUNT})"
    echo "$TOP_DIRS"
    echo ""
} >> "$AUDIT_LOG" 2>/dev/null || true

rm -rf "$TARGET" 2>>"$AUDIT_LOG"

if [ ! -d "$TARGET" ]; then
    echo "🧹 remux-backup self-cleanup: deleted $SIZE / ${FILECOUNT} files from $TARGET (stale >${GRACE_HOURS}h). Audit: $AUDIT_LOG"
    exit 1   # non-empty stdout -> cron delivers the alert
else
    echo "⚠️ remux-backup watchdog: found stale folder but DELETE FAILED. Manual attention needed: $TARGET (${SIZE})"
    exit 99
fi

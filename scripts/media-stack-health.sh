#!/bin/bash
# media-stack-health.sh — watchdog for the suvannmedia stack
#
# Watchdog pattern: SILENT (no output) when everything is healthy.
# Any non-empty stdout = something needs attention; cron delivers it verbatim.
#
# Checks:
#   1. Media pool mounted + disk usage under threshold
#   2. HTTP probe of every web service (systemctl lies after enclosure dropouts —
#      a live process with closed ports is the known failure mode, so we curl)
#   3. Failed systemd units (system + user scope), stale orphans excluded
#
# Exit codes: 0 = healthy/silent, 1 = problems found (alert emitted)

set -uo pipefail

export XDG_RUNTIME_DIR=/run/user/$(id -u)   # needed for systemctl --user outside login sessions

MEDIA_POOL=/var/mnt/media
DISK_ALERT_PCT=90
PROBLEMS=""

add_problem() { PROBLEMS="${PROBLEMS}  - $1\n"; }

# ─── 1. Media pool ──────────────────────────────────────────────────────────
if ! mountpoint -q "$MEDIA_POOL" 2>/dev/null; then
    add_problem "MEDIA POOL NOT MOUNTED: $MEDIA_POOL — all services will be serving stale/empty data"
else
    USAGE=$(df --output=pcent "$MEDIA_POOL" 2>/dev/null | tail -1 | tr -dc '0-9')
    if [ -n "${USAGE:-}" ] && [ "$USAGE" -ge "$DISK_ALERT_PCT" ]; then
        add_problem "Media pool at ${USAGE}% capacity (threshold ${DISK_ALERT_PCT}%) — downloads will fail soon"
    fi
fi

# ─── 2. HTTP probes: name:port (any real HTTP response = alive; 000 = dead) ──
SERVICES="jellyfin:8096 sonarr:8989 radarr:7878 prowlarr:9696 sabnzbd:8085 bazarr:6767 jellyseerr:5055 fileflows:5000 flaresolverr:8191"
for entry in $SERVICES; do
    name=${entry%%:*}
    port=${entry##*:}
    code=$(curl --max-time 8 -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" 2>/dev/null || echo 000)
    case "$code" in
        000|4[0-9][0-9]|5[0-9][0-9])
            # 4xx/5xx on root path is unusual for these apps but the process IS up;
            # only treat connection failure (000) as dead, log others as degraded.
            if [ "$code" = "000" ]; then
                add_problem "$name NOT RESPONDING on port $port (connection failed)"
            else
                add_problem "$name degraded: HTTP $code on port $port (process up, app erroring)"
            fi
            ;;
    esac
done

# ─── 3. Failed units (system + user scope) ──────────────────────────────────
# Stale orphans (unit file deleted, state record left behind — e.g. gluetun,
# old system-scope fileflows) would alert forever; auto-reset those silently.
check_failed_units() {
    local scope_flag="$1" sudo_prefix="$2" unit loadstate
    for unit in $(systemctl $scope_flag --failed --no-legend --plain 2>/dev/null | awk '{print $1}'); do
        # Skip Bazzite/SteamOS auto-generated app units (flatpak/gamepad integration,
        # e.g. input-remapper-autoload) — not part of the media stack, always noisy.
        case "$unit" in
            app-*|app\-* ) continue ;;
        esac
        loadstate=$(systemctl $scope_flag show -p LoadState --value "$unit" 2>/dev/null)
        if [ "$loadstate" = "not-found" ]; then
            # Orphaned state record — no unit file exists. Harmless to clear.
            $sudo_prefix systemctl reset-failed "$unit" 2>/dev/null || true
        else
            add_problem "Failed systemd unit: $unit (scope: ${scope_flag:-system})"
        fi
    done
}
check_failed_units "" "sudo -n"
check_failed_units "--user" ""

# ─── Verdict ────────────────────────────────────────────────────────────────
if [ -n "$PROBLEMS" ]; then
    echo "🚨 suvannmedia health check — $(date '+%Y-%m-%d %H:%M'):"
    printf "%b" "$PROBLEMS"
    exit 1
fi
exit 0

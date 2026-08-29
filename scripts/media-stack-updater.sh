#!/bin/bash
# media-stack-updater.sh — Checks for updates to all media-stack container images
# Runs: podman pull on :latest images; rebuilds FileFlows custom image; checks cloudflared binary.
# Designed for weekly cron. Reports to STDOUT — silent if nothing new.
#
# Exit codes:
#   0  — success (whether or not updates were applied)
#   99 — real error (failed pull, failed restart, etc.)
# NOTE: previously exited 1 when updates were applied; the cron scheduler read
# that as last_status=error. Fixed Aug 2026 — non-zero now means actual failure.

set -uo pipefail

UPDATED=false
ERRORS=0
GIT_REPO=/home/skim/JellyFin

# ─── Standard containers (just pull :latest) ─────────────────────────────────
check_container_update() {
    local name="$1" full_image="$2"
    local old_id new_id pull_rc

    old_id=$(podman image inspect "$full_image" --format '{{.Id}}' 2>/dev/null || echo 'none')
    echo "  [$name] pulling ${full_image}..."
    podman pull "$full_image" >/dev/null 2>&1
    pull_rc=$?
    new_id=$(podman image inspect "$full_image" --format '{{.Id}}' 2>/dev/null || echo 'none')

    if [ $pull_rc -ne 0 ]; then
        echo "  ⚠️ [$name] PULL FAILED (rc=$pull_rc) — left on current image"
        ERRORS=$((ERRORS+1))
        return 0
    fi

    if [ "$old_id" != "$new_id" ]; then
        echo "  ✅ [$name] updated: ${old_id:0:12} → ${new_id:0:12}"
        sudo systemctl restart "$name" || { echo "  ⚠️  [$name] restart failed"; ERRORS=$((ERRORS+1)); }
        UPDATED=true
    else
        echo "  □ [$name] current"
    fi
}

echo "═══════════════════════════════════════════════"
echo " Media Stack Updater — $(date '+%Y-%m-%d %H:%M')"
echo "═══════════════════════════════════════════════"
echo ""

# ─── 8 standard containers ──────────────────────────────────────────────────
check_container_update "jellyfin"    "docker.io/jellyfin/jellyfin:latest"
check_container_update "jellyseerr"  "docker.io/fallenbagel/jellyseerr:latest"
check_container_update "sabnzbd"     "docker.io/linuxserver/sabnzbd:latest"
check_container_update "prowlarr"    "docker.io/linuxserver/prowlarr:latest"
check_container_update "radarr"      "docker.io/linuxserver/radarr:latest"
check_container_update "sonarr"      "docker.io/linuxserver/sonarr:latest"
check_container_update "bazarr"      "docker.io/linuxserver/bazarr:latest"

# ─── FileFlows — custom image rebuild (USER unit, not system) ────────────────
export XDG_RUNTIME_DIR=/run/user/$(id -u)   # required for systemctl --user outside a login session

echo ""
echo "  [fileflows] checking upstream..."
FF_OLD=$(podman image inspect "localhost/fileflows-amd-vaapi:latest" --format '{{.Id}}' 2>/dev/null || echo 'none')
FF_UPSTREAM_OLD=$(podman image inspect "docker.io/revenz/fileflows:latest" --format '{{.Id}}' 2>/dev/null || echo 'none')

podman pull docker.io/revenz/fileflows:latest >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "  ⚠️ [fileflows] upstream PULL FAILED — left on current image"
    ERRORS=$((ERRORS+1))
else
FF_UPSTREAM_NEW=$(podman image inspect "docker.io/revenz/fileflows:latest" --format '{{.Id}}' 2>/dev/null || echo 'none')

if [ "$FF_UPSTREAM_OLD" != "$FF_UPSTREAM_NEW" ]; then
    echo "  ✅ [fileflows] upstream updated: ${FF_UPSTREAM_OLD:0:12} → ${FF_UPSTREAM_NEW:0:12}"
    # Rebuild custom image
    podman rm -f ff-builder 2>/dev/null || true
    podman run -d --name ff-builder docker.io/revenz/fileflows:latest >/dev/null
    sleep 5
    podman exec -u 0 ff-builder apt update >/dev/null 2>&1
    podman exec -u 0 ff-builder apt install -y ffmpeg vainfo mesa-va-drivers intel-media-va-driver-non-free >/dev/null 2>&1
    podman commit ff-builder localhost/fileflows-amd-vaapi:latest >/dev/null
    podman rm -f ff-builder >/dev/null

    FF_NEW=$(podman image inspect "localhost/fileflows-amd-vaapi:latest" --format '{{.Id}}')
    if [ "$FF_OLD" != "$FF_NEW" ]; then
        echo "  ✅ [fileflows] custom image rebuilt: ${FF_OLD:0:12} → ${FF_NEW:0:12}"
        systemctl --user restart fileflows.service || { echo "  ⚠️ [fileflows] restart failed"; ERRORS=$((ERRORS+1)); }
        UPDATED=true
    fi
else
    echo "  □ [fileflows] current"
fi
fi

# ─── Cloudflared — check binary version from GitHub ─────────────────────────
echo ""
echo "  [cloudflared] checking binary..."
INSTALLED_VER=$(/usr/local/bin/cloudflared version 2>/dev/null | head -1 | grep -oP '\d{4}\.\d+\.\d+' || echo 'unknown')
# Grab the latest release from GitHub (no API token needed for public release data)
LATEST_URL=$(curl -sL --max-time 10 \
    'https://api.github.com/repos/cloudflare/cloudflared/releases/latest' \
    -H 'Accept: application/vnd.github.v3+json' 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); r=[a for a in d.get('assets',[]) if 'cloudflared-linux-amd64' in a.get('name','')]; print(r[0]['browser_download_url'] if r else '')" 2>/dev/null || echo '')
LATEST_TAG=$(curl -sL --max-time 10 \
    'https://api.github.com/repos/cloudflare/cloudflared/releases/latest' \
    -H 'Accept: application/vnd.github.v3+json' 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tag_name',''))" 2>/dev/null || echo '')

if [ -n "$LATEST_URL" ] && [ -n "$LATEST_TAG" ]; then
    if echo "$INSTALLED_VER" | grep -q "$LATEST_TAG" 2>/dev/null; then
        echo "  □ [cloudflared] current ($INSTALLED_VER)"
    else
        echo "  ✅ [cloudflared] new version available: $LATEST_TAG"
        curl -sL --max-time 60 -o /tmp/cloudflared "$LATEST_URL"
        chmod +x /tmp/cloudflared
        cp /tmp/cloudflared /home/skim/.local/bin/cloudflared
        sudo cp /tmp/cloudflared /usr/local/bin/cloudflared
        rm -f /tmp/cloudflared
        sudo systemctl restart cloudflared || { echo "  ⚠️ [cloudflared] restart failed"; ERRORS=$((ERRORS+1)); }
        UPDATED=true
    fi
else
    echo "  ⚠️  [cloudflared] GitHub API unreachable — skipping"
fi

# ─── Sync updated service files to repo ──────────────────────────────────────
if $UPDATED; then
    echo ""
    echo "═══ Syncing service files to repo ═══"
    for f in jellyfin jellyseerr sabnzbd prowlarr radarr sonarr bazarr fileflows cloudflared; do
        if [ -f "/etc/systemd/system/$f.service" ]; then
            sudo cp "/etc/systemd/system/$f.service" "$GIT_REPO/systemd/$f.service"
        fi
    done
    sudo cp /etc/systemd/system/var-mnt-jellyfin.mount "$GIT_REPO/systemd/" 2>/dev/null || true
    sudo chown -R skim:skim "$GIT_REPO/systemd/"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══ Done ═══"
echo "Updates applied: $UPDATED"
echo "Errors: $ERRORS"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M')"
[ "$ERRORS" -gt 0 ] && exit 99 || exit 0
#!/bin/bash
# media-stack-updater.sh — Reconciles pinned media-stack container images
# Runs: podman pull on the reviewed digest refs; rebuilds the pinned FileFlows
# custom image; checks cloudflared. Designed for weekly cron. Reports to STDOUT.
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

# ─── Pinned rootful containers ───────────────────────────────────────────────
check_container_update() {
    local name="$1" full_image="$2"
    shift 2
    local -a podman_cmd=("$@")
    local old_id new_id pull_rc

    old_id=$("${podman_cmd[@]}" image inspect "$full_image" --format '{{.Id}}' 2>/dev/null || echo 'none')
    echo "  [$name] pulling ${full_image}..."
    "${podman_cmd[@]}" pull "$full_image" >/dev/null 2>&1
    pull_rc=$?
    new_id=$("${podman_cmd[@]}" image inspect "$full_image" --format '{{.Id}}' 2>/dev/null || echo 'none')

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

# ─── Pinned rootful containers ───────────────────────────────────────────────
check_container_update "jellyfin"    "docker.io/jellyfin/jellyfin@sha256:78d3ea1207d1322471fcac39a614f004f2ccf7e878f95ab2977d752f07e4dd7e" sudo podman
check_container_update "jellyseerr"  "docker.io/seerr/seerr@sha256:f4768de5f616248d723e05891f3345a1402123775d03bf0890dbfedc0831bda1" sudo podman
check_container_update "sabnzbd"     "docker.io/linuxserver/sabnzbd@sha256:948ea3dc45d68943ec14b33ba37ffa1488da3e9837bf3ca0f75621e971614d85" sudo podman
check_container_update "prowlarr"    "docker.io/linuxserver/prowlarr@sha256:c96b56d94d116a9f4de94bc23d3381689492e6c3cfb7435320e8d982e406f99a" sudo podman
check_container_update "radarr"      "docker.io/linuxserver/radarr@sha256:adb6c09d6b729ea5e642c99cea35af72702ef476bf4763f153299ac5db9f0b4f" sudo podman
check_container_update "sonarr"      "docker.io/linuxserver/sonarr@sha256:a5c1a5fecbef946927ab90ad68df319ac5fe644057e5fc18cd993f01ac07b2b2" sudo podman
check_container_update "bazarr"      "docker.io/linuxserver/bazarr@sha256:d24bd0048c759a468970989e9df11a6b96a7628d556d00f923e60a35ba59237b" sudo podman
check_container_update "flaresolverr" "docker.io/flaresolverr/flaresolverr@sha256:c80ae007ce2ccdcd217a12426e4f039ef763ff90738c808d38810c3e59323767" sudo podman

# ─── FileFlows — custom image rebuild (USER unit, not system) ────────────────
export XDG_RUNTIME_DIR=/run/user/$(id -u)   # required for systemctl --user outside a login session

echo ""
echo "  [fileflows] checking upstream..."
FF_IMAGE="docker.io/revenz/fileflows@sha256:1f412e4e2b411a18d25538095629ef870185ea602f9840caab06088dec8231ae"
FF_OLD=$(podman image inspect "localhost/fileflows-amd-vaapi:latest" --format '{{.Id}}' 2>/dev/null || echo 'none')
FF_UPSTREAM_OLD=$(podman image inspect "$FF_IMAGE" --format '{{.Id}}' 2>/dev/null || echo 'none')

podman pull "$FF_IMAGE" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "  ⚠️ [fileflows] upstream PULL FAILED — left on current image"
    ERRORS=$((ERRORS+1))
else
FF_UPSTREAM_NEW=$(podman image inspect "$FF_IMAGE" --format '{{.Id}}' 2>/dev/null || echo 'none')

if [ "$FF_UPSTREAM_OLD" != "$FF_UPSTREAM_NEW" ]; then
    echo "  ✅ [fileflows] upstream updated: ${FF_UPSTREAM_OLD:0:12} → ${FF_UPSTREAM_NEW:0:12}"
    # Rebuild custom image from the reviewed upstream digest.
    podman rm -f ff-builder 2>/dev/null || true
    podman run -d --name ff-builder "$FF_IMAGE" >/dev/null
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
    for f in jellyfin jellyseerr sabnzbd prowlarr radarr sonarr bazarr flaresolverr cloudflared; do
        if [ -f "/etc/systemd/system/$f.service" ]; then
            sudo cp "/etc/systemd/system/$f.service" "$GIT_REPO/systemd/$f.service"
        fi
    done
    # FileFlows is a USER unit — sync from the user bus dir, not /etc/systemd/system/
    if [ -f /home/skim/.config/systemd/user/fileflows.service ]; then
        cp /home/skim/.config/systemd/user/fileflows.service "$GIT_REPO/systemd/fileflows.service"
    fi

    sudo chown -R skim:skim "$GIT_REPO/systemd/"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══ Done ═══"
echo "Updates applied: $UPDATED"
echo "Errors: $ERRORS"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M')"
[ "$ERRORS" -gt 0 ] && exit 99 || exit 0
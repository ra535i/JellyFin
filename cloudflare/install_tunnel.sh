#!/bin/bash
# Cloudflare Tunnel install — suvannmedia.com
# RUN AS USER (not root):  bash cloudflare/install_tunnel.sh
#
# Prerequisites:
#   - cloudflared binary at ~/.local/bin/cloudflared
#   - Cloudflare API token with Zone:DNS:Edit + Tunnel:Edit permissions
#   - cloudflare/config.yml.template customized with your tunnel UUID
#
# This script:
#   1. Downloads cloudflared binary to ~/.local/bin/
#   2. Authenticates with your API token
#   3. Creates the tunnel (or reuses existing)
#   4. Saves credentials.json
#   5. Creates DNS CNAME records for all subdomains
#   6. Installs the user systemd service
#   7. Starts it

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

# ===== CONFIGURE THESE =====
DOMAIN="suvannmedia.com"
TUNNEL_NAME="suvannmedia-tunnel"
CF_ZONE_ID="1b800ffd1d4d0fa188b27729d6e7d1d1"
CF_ACCOUNT_ID="fe5505252424944f4111b7059bcab9a1"
# CF_API_TOKEN — set as env var or paste below
: "${CF_API_TOKEN:=""}"

SUBDOMAINS=(jellyfin jellyseerr sabnzbd prowlarr radarr sonarr bazarr fileflows)

# ===== Install cloudflared =====
echo "═══ INSTALLING CLOUDFLARED ═══"
if ! command -v ~/.local/bin/cloudflared &>/dev/null; then
    mkdir -p ~/.local/bin
    curl -sL --max-time 60 \
        -o ~/.local/bin/cloudflared \
        "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    chmod +x ~/.local/bin/cloudflared
    echo "cloudflared installed"
else
    echo "cloudflared already present"
fi

# ===== Auth =====
if [ -z "$CF_API_TOKEN" ]; then
    echo "ERROR: CF_API_TOKEN not set. Run:  export CF_API_TOKEN='your-token'"
    exit 1
fi

echo "═══ AUTHENTICATING ═══"
~/.local/bin/cloudflared tunnel login --token "$CF_API_TOKEN" 2>/dev/null || true

# ===== Create or reuse tunnel =====
echo "═══ TUNNEL ═══"
TUNNEL_ID=$(
    ~/.local/bin/cloudflared tunnel list 2>/dev/null \
    | grep "$TUNNEL_NAME" | awk '{print $1}' \
    || true
)
if [ -z "$TUNNEL_ID" ]; then
    TUNNEL_ID=$(~/.local/bin/cloudflared tunnel create "$TUNNEL_NAME" 2>&1 | grep -oP '[a-f0-9-]{36}' | head -1)
    echo "Created tunnel: $TUNNEL_ID"
else
    echo "Reusing existing tunnel: $TUNNEL_ID"
fi

CRED_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"
if [ ! -f "$CRED_FILE" ]; then
    # Find creds — could be in ~/.cloudflared/
    CRED_FILE=$(find ~/.cloudflared/ -name "*.json" ! -name "cert*" 2>/dev/null | head -1)
fi
echo "Credentials: $CRED_FILE"

# ===== Copy config =====
echo "═══ CONFIG ═══"
mkdir -p ~/.cloudflared
cp "$REPO/cloudflare/config.yml.template" ~/.cloudflared/config.yml
# Update tunnel UUID inline
sed -i "s/tunnel: .*/tunnel: $TUNNEL_ID/" ~/.cloudflared/config.yml
# Update credentials-file path
sed -i "s|credentials-file: .*|credentials-file: $CRED_FILE|" ~/.cloudflared/config.yml

# ===== DNS records =====
echo "═══ DNS RECORDS ═══"
for sub in "${SUBDOMAINS[@]}"; do
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"CNAME\",\"name\":\"$sub\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"proxied\":true}" \
        >/dev/null 2>&1 && echo "  $sub.$DOMAIN -> tunnel" || echo "  $sub.$DOMAIN SKIP (may exist)"
done

# ===== Systemd service (user-level) =====
echo "═══ SYSTEMD ═══"
cp "$REPO/cloudflare/cloudflared.service" ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable cloudflared.service
systemctl --user restart cloudflared.service

# Enable linger so user services start at boot
loginctl enable-linger "$(whoami)" 2>/dev/null || true

echo "═══ VERIFY ═══"
sleep 3
systemctl --user is-active cloudflared.service && echo "✅ Tunnel running" || echo "❌ Tunnel failed"

echo "═══ DONE ═══"
echo "Next: run cloudflare/setup_access.sh to add Cloudflare Access gates for admin services."
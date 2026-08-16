#!/bin/bash
# Cloudflare Access gate setup — suvannmedia.com
# RUN AFTER cloudflare/install_tunnel.sh
# RUN AS USER:  bash cloudflare/setup_access.sh
#
# Creates Cloudflare Access applications for admin services:
#   SABnzbd, Prowlarr, Radarr, Sonarr, Bazarr
# Protected by Google OAuth, restricted to YOUR gmail.
#
# Jellyfin and Jellyseerr are intentionally left OPEN (no Access gate)
# so mobile apps and family can connect directly.

set -euo pipefail

# ===== CONFIGURE THESE =====
DOMAIN="suvannmedia.com"
CF_ACCOUNT_ID="fe5505252424944f4111b7059bcab9a1"
ADMIN_EMAIL="suvann540i@gmail.com"
SESSION_DURATION="24h"
# CF_API_TOKEN needs Access:Apps:Edit + Access:Apps:Read + Access:Policies:Edit permissions
: "${CF_API_TOKEN:=""}"

# Admin services — behind Google OAuth
ADMIN_SERVICES=(sabnzbd prowlarr radarr sonarr bazarr)

if [ -z "$CF_API_TOKEN" ]; then
    echo "ERROR: CF_API_TOKEN not set. Run:  export CF_API_TOKEN='your-token'"
    exit 1
fi

echo "═══ CREATING ACCESS GATES ═══"

for sub in "${ADMIN_SERVICES[@]}"; do
    FQDN="$sub.$DOMAIN"
    echo "  Creating gate for $FQDN..."

    RESP=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/access/apps" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$FQDN\",
            \"domain\": \"$FQDN\",
            \"type\": \"self_hosted\",
            \"session_duration\": \"$SESSION_DURATION\",
            \"policies\": [{
                \"name\": \"Only me\",
                \"decision\": \"allow\",
                \"include\": [{\"email\": {\"email\": \"$ADMIN_EMAIL\"}}]
            }]
        }")

    if echo "$RESP" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin)['success'] else 1)" 2>/dev/null; then
        echo "    ✅ Gate created"
    else
        echo "    ⚠️  Failed (may already exist)"
    fi
done

echo "═══ DONE ═══"
echo "Admin services are now gated behind Google OAuth."
echo "Jellyfin and Jellyseerr are OPEN (no gate)."
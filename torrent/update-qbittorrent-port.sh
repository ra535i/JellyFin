#!/bin/sh
set -eu

port="${1:?forwarded port required}"
interface="${2:?VPN interface required}"
url="http://127.0.0.1:8080/api/v2/app/setPreferences"
payload=$(printf 'json={"listen_port":%s,"current_network_interface":"%s","random_port":false,"upnp":false}' "$port" "$interface")

# Gluetun generally receives its PIA port before qBittorrent finishes starting.
# Retry until qBittorrent's localhost API becomes available.
attempt=0
while [ "$attempt" -lt 90 ]; do
    if wget -qO- --timeout=5 --post-data "$payload" "$url" >/dev/null 2>&1; then
        echo "qBittorrent listen port set to $port on $interface"
        exit 0
    fi
    attempt=$((attempt + 1))
    sleep 2
done

echo "qBittorrent API did not accept the PIA forwarded-port update" >&2
exit 1

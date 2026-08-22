#!/bin/bash
# Helper to access qBittorrent web UI while it's behind Gluetun VPN
# Usage: ./qb-webui.sh [start|stop|status]
# When running, access qBittorrent at http://localhost:18080

QB_PORT=18080
CONTAINER=qbittorrent

case "${1:-status}" in
  start)
    echo "Starting qBittorrent web UI proxy on port $QB_PORT..."
    podman exec -d "$CONTAINER" socat TCP-LISTEN:$QB_PORT,fork TCP:127.0.0.1:8080 2>/dev/null || {
      # socat might not be in the container, use podman port forward instead
      echo "Falling back to direct connection..."
      echo "Run: podman exec -it $CONTAINER sh"
      echo "Then: socat TCP-LISTEN:18080,fork TCP:127.0.0.1:8080"
      echo "Then access: http://localhost:18080"
    }
    echo "Web UI should be at http://localhost:$QB_PORT"
    ;;
  stop)
    echo "Stopping proxy..."
    podman exec "$CONTAINER" killall socat 2>/dev/null || true
    ;;
  status)
    if podman ps --format '{{.Names}}' | grep -q "^$CONTAINER$"; then
      echo "qBittorrent container: RUNNING"
      echo "To access web UI:"
      echo "  1. Run: podman exec -d $CONTAINER socat TCP-LISTEN:18080,fork TCP:127.0.0.1:8080"
      echo "  2. Open http://localhost:18080"
      echo ""
      echo "Default login: admin / adminadmin"
    else
      echo "qBittorrent container: NOT RUNNING"
      echo "Start with: sudo systemctl start gluetun qbittorrent"
    fi
    ;;
esac
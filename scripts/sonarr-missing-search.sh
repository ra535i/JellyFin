#!/usr/bin/env bash
# sonarr-missing-search.sh — rate-limited historical backfill for Sonarr.
#
# Sonarr RSS sync only sees newly posted releases; it does not periodically
# search its entire existing Missing list. This job advances through monitored
# missing episodes in small daily batches so historical backfill does not hammer
# Prowlarr/indexers.
set -Eeuo pipefail

SONARR_URL=${SONARR_URL:-http://127.0.0.1:8989}
SONARR_CONFIG=${SONARR_CONFIG:-/home/skim/jellyfin-configs/sonarr/config.xml}
STATE_DIR=${STATE_DIR:-/home/skim/jellyfin-configs/sonarr-missing-search}
BATCH_SIZE=${BATCH_SIZE:-10}
DRY_RUN=false

usage() {
  printf 'usage: %s [--dry-run]\n' "$0" >&2
}

case "${1:-}" in
  '') ;;
  --dry-run) DRY_RUN=true ;;
  *) usage; exit 2 ;;
esac

[[ $BATCH_SIZE =~ ^[1-9][0-9]*$ ]] || { echo 'BATCH_SIZE must be a positive integer' >&2; exit 2; }
[[ -r $SONARR_CONFIG ]] || { echo "Sonarr config is not readable: $SONARR_CONFIG" >&2; exit 1; }

mkdir -p "$STATE_DIR"
API_KEY=$(python3 - "$SONARR_CONFIG" <<'PY'
import sys
import xml.etree.ElementTree as ET

key = ET.parse(sys.argv[1]).findtext('ApiKey')
if not key:
    raise SystemExit('Sonarr ApiKey is missing from config.xml')
print(key)
PY
)

WORK_DIR=$(mktemp -d "$STATE_DIR/sonarr-missing-search.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT
SONARR_AUTH_HEADER="X-Api-Ke""y: $API_KEY"

curl -fsS --max-time 60 -H "$SONARR_AUTH_HEADER" \
  "$SONARR_URL/api/v3/wanted/missing?page=1&pageSize=1000&sortKey=airDateUtc&sortDirection=ascending" \
  -o "$WORK_DIR/missing.json"

python3 - "$WORK_DIR/missing.json" "$STATE_DIR/cursor.json" "$BATCH_SIZE" > "$WORK_DIR/selection.json" <<'PY'
import json
import sys
from pathlib import Path

missing_path = Path(sys.argv[1])
cursor_path = Path(sys.argv[2])
batch_size = int(sys.argv[3])
payload = json.loads(missing_path.read_text())
episodes = [episode for episode in payload.get('records', []) if episode.get('monitored')]
if not episodes:
    print(json.dumps({'episodeIds': [], 'totalMissing': payload.get('totalRecords', 0)}))
    raise SystemExit

cursor = {}
if cursor_path.exists():
    try:
        cursor = json.loads(cursor_path.read_text())
    except json.JSONDecodeError:
        pass
last_id = cursor.get('lastEpisodeId')
start = next((i + 1 for i, episode in enumerate(episodes) if episode['id'] == last_id), 0)
selected = episodes[start:start + batch_size] or episodes[:batch_size]
print(json.dumps({
    'episodeIds': [episode['id'] for episode in selected],
    'lastEpisodeId': selected[-1]['id'],
    'totalMissing': payload.get('totalRecords', len(episodes)),
}))
PY

EPISODE_COUNT=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["episodeIds"]))' "$WORK_DIR/selection.json")
TOTAL_MISSING=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["totalMissing"])' "$WORK_DIR/selection.json")

if [[ $EPISODE_COUNT -eq 0 ]]; then
  printf 'Sonarr missing-search: no monitored missing episodes (reported missing: %s)\n' "$TOTAL_MISSING"
  exit 0
fi

if $DRY_RUN; then
  printf 'Sonarr missing-search dry run: would search %s monitored episodes (reported missing: %s)\n' \
    "$EPISODE_COUNT" "$TOTAL_MISSING"
  exit 0
fi

COMMAND=$(python3 -c 'import json,sys; x=json.load(open(sys.argv[1])); print(json.dumps({"name":"EpisodeSearch", "episodeIds":x["episodeIds"]}))' "$WORK_DIR/selection.json")
RESPONSE=$(curl -fsS --max-time 60 -X POST \
  -H "$SONARR_AUTH_HEADER" -H 'Content-Type: application/json' \
  --data "$COMMAND" "$SONARR_URL/api/v3/command")

python3 - "$WORK_DIR/selection.json" "$STATE_DIR/cursor.json" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

selection = json.loads(Path(sys.argv[1]).read_text())
Path(sys.argv[2]).write_text(json.dumps({
    'lastEpisodeId': selection['lastEpisodeId'],
    'updatedAt': datetime.now(timezone.utc).isoformat(),
}) + '\n')
PY

printf '%s' "$RESPONSE" | python3 -c 'import json,sys; response=json.load(sys.stdin); print("Sonarr missing-search: queued EpisodeSearch command {} for {} episodes (reported missing: {})".format(response.get("id", "unknown"), sys.argv[1], sys.argv[2]))' "$EPISODE_COUNT" "$TOTAL_MISSING"
#!/bin/bash
# FileFlows flow importer — runs inside the FileFlows container.
# 
# Usage after a rebuild:
#   podman cp /home/skim/JellyFin/fileflows/flows fileflows:/tmp/flows
#   podman cp /home/skim/JellyFin/fileflows/import_flows.sh fileflows:/tmp/
#   podman exec fileflows bash /tmp/import_flows.sh
#
# Or automatically via install_arr_stack.sh after the stack starts.

set -euo pipefail

FF_BASE="http://localhost:5000"
FLOW_DIR="/tmp/flows"

if [ ! -d "$FLOW_DIR" ] || [ -z "$(ls -A "$FLOW_DIR"/*.json 2>/dev/null)" ]; then
  echo "FILEFLOWS IMPORT: no flow files found in $FLOW_DIR — skipping"
  exit 0
fi

echo "═══ FileFlows: importing flows from $FLOW_DIR ═══"

for f in "$FLOW_DIR"/*.json; do
  name=$(basename "$f" .json | sed 's/_/ /g')
  echo "  Importing $name..."

  # PUT the flow JSON directly to /api/flow
  # This requires the flow JSON to have a valid Uuid field
  json_str=$(cat "$f")
  result=$(curl -sS -o /dev/null -w "%{http_code}" -X PUT \
    -H "Content-Type: application/json" \
    --data-binary "$json_str" "$FF_BASE/api/flow" 2>/dev/null || echo "FAILED")

  if [ "$result" = "200" ]; then
    echo "    ✅ Imported: $name"
  else
    echo "    ⚠️  HTTP $result — may need manual import via UI (Flows → Import)"
  fi
done

echo "═══ Import complete ═══"
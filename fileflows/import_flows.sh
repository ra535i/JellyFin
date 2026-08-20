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
  json_str=$(python3 -c "import json; s=open('$f').read(); print(json.dumps(s))")
  result=$(curl -sS -X POST -H 'Content-Type: application/json' \
    --data-binary "$json_str" "$FF_BASE/api/flow/import" 2>/dev/null || echo '{"Name":"HTTP_FAIL"}')
  imported=$(echo "$result" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('Name', 'PARSE_FAIL'))
except Exception:
    print('PARSE_FAIL')
" 2>/dev/null || echo "FAILED")
  echo "  $name -> $imported"
done

echo "═══ Import complete ═══"
echo "Verify: curl -s $FF_BASE/api/flow | python3 -c \"import sys,json; [print(json.loads(l,strict=False)['Name']) for l in sys.stdin]\""
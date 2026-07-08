#!/usr/bin/env bash
# Publish every agent under this directory to an Omnigent server.
#
# Each agent is one directory holding a config.yaml (the agent spec). The
# server has no standalone agent-upload endpoint: an agent is created by a
# multipart session create, and it lives as long as that anchor session —
# DO NOT delete the "(agent anchor)" sessions this script creates, or the
# agent and every session running on it are cascade-deleted.
#
# Re-running publishes a NEW agent (new agent_id) per directory; old ones
# keep working for their existing sessions.
#
# Usage: ./publish.sh [server-url]        # default http://localhost:8000
set -euo pipefail

SERVER="${1:-http://localhost:8000}"
DIR="$(cd "$(dirname "$0")" && pwd)"

curl -sf "$SERVER/health" >/dev/null || {
  echo "error: $SERVER/health not reachable (is the port-forward up?)" >&2
  exit 1
}

for agent_dir in "$DIR"/*/; do
  name="$(basename "$agent_dir")"
  [ -f "$agent_dir/config.yaml" ] || continue
  bundle="$(mktemp -t "omnigent-agent-$name.XXXXXX").tar.gz"
  tar czf "$bundle" -C "$agent_dir" .
  resp="$(curl -s -X POST "$SERVER/v1/sessions" \
    -F "metadata={\"title\":\"$name (agent anchor - do not delete)\"}" \
    -F "bundle=@$bundle")"
  rm -f "$bundle"
  echo "$name: $resp"
done

echo
echo "Create sessions on an agent with:"
echo "  curl -X POST $SERVER/v1/sessions -H 'Content-Type: application/json' \\"
echo "    -d '{\"agent_id\": \"<agent_id above>\", \"host_type\": \"managed\"}'"
echo "or pick the agent in the web UI (New Sandbox)."

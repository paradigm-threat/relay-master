#!/usr/bin/env bash
# Aggregate catalog/repos/*.json into legacy relay-catalog.json for backward compatibility.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_DIR="${ROOT}/catalog/repos"
OUT="${ROOT}/relay-catalog.json"

if [[ ! -d "$REPOS_DIR" ]]; then
  echo "build-relay-catalog-json: missing $REPOS_DIR" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "build-relay-catalog-json: jq required" >&2
  exit 1
fi

repos_json="{}"
for f in "$REPOS_DIR"/*.json; do
  [[ -f "$f" ]] || continue
  name="$(basename "$f" .json)"
  root="$(jq -r '.relay_root_commit // empty' "$f")"
  url="$(jq -r '.forge_url // .url // empty' "$f")"
  branch="$(jq -r '.publish_branch // .branch // "main"' "$f")"
  if [[ -z "$root" || ${#root} -ne 40 ]]; then
    echo "build-relay-catalog-json: $f missing relay_root_commit" >&2
    exit 1
  fi
  entry=$(jq -n \
    --arg url "$url" \
    --arg root "$root" \
    --arg branch "$branch" \
    '{url: $url, relayRootCommit: $root, branch: $branch}')
  repos_json=$(echo "$repos_json" | jq --arg name "$name" --argjson entry "$entry" '. + {($name): $entry}')
done

jq -n --argjson repos "$repos_json" '{repos: $repos}' > "$OUT"
echo "build-relay-catalog-json: wrote $OUT ($(echo "$repos_json" | jq 'keys | length') repos)"

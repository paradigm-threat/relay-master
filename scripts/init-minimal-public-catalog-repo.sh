#!/usr/bin/env bash
# Create a new Git repo whose only commit is README.md (public catalog stub).
# Usage: ./scripts/init-minimal-public-catalog-repo.sh OUTPUT_DIR [REPO_TITLE]
# Prints relayRootCommit (40 hex) on stdout last line prefixed with relayRootCommit=
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-}"
TITLE="${2:-Catalog stub}"

if [[ -z "$OUT" ]]; then
  echo "Usage: $0 OUTPUT_DIR [REPO_TITLE]" >&2
  exit 1
fi

if [[ -e "$OUT" ]]; then
  echo "Refusing to clobber existing path: $OUT" >&2
  exit 1
fi

mkdir -p "$OUT"
cat >"$OUT/README.md" <<EOF
# ${TITLE}

This repository is a **minimal public face** for Relay’s **relay-master** catalog.

Nodes sync from here with \`git clone --depth 1\` (see \`relay-master/scripts/sync-relay-catalog.sh\`).
**Do not publish restricted content** to this remote; push full trees to relay with \`git push git://<host>:9418/<repo>.git\`.
EOF

git -C "$OUT" init -b main
git -C "$OUT" add README.md
git -C "$OUT" -c user.email=catalog@relay.local -c user.name="Relay catalog" \
  commit -m "Public catalog stub (README only)"
H="$(git -C "$OUT" rev-parse HEAD)"
echo "Created $OUT" >&2
echo "relayRootCommit=$H"

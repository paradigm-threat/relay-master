#!/usr/bin/env bash
# Add a submodule to relay-master with relayRootCommit from the cloned tree.
# Usage: ./scripts/add-catalog-submodule.sh REPO_NAME CLONE_URL [BRANCH]
# Requires network access to CLONE_URL (GitLab token/SSH as appropriate).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NAME="${1:-}"
URL="${2:-}"
BRANCH="${3:-main}"

if [[ -z "$NAME" || -z "$URL" ]]; then
  echo "Usage: $0 REPO_NAME CLONE_URL [BRANCH]" >&2
  exit 1
fi

PATH_UNDER="repos/${NAME}"
if [[ -e "$PATH_UNDER" ]]; then
  echo "Path $PATH_UNDER already exists" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git clone --depth=500 --branch "$BRANCH" "$URL" "$TMP/clone"
ROOT_COMMIT=$(git -C "$TMP/clone" rev-list --max-parents=0 -n 1 "$BRANCH")
if [[ ${#ROOT_COMMIT} -ne 40 ]]; then
  echo "Could not resolve root commit" >&2
  exit 1
fi

git submodule add --name "$NAME" "$URL" "$PATH_UNDER"
git config -f .gitmodules "submodule.${NAME}.relayRootCommit" "$ROOT_COMMIT"
git add .gitmodules "$PATH_UNDER"
echo "Added submodule $NAME with relayRootCommit=$ROOT_COMMIT — commit when ready."

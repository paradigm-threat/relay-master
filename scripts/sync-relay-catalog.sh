#!/usr/bin/env bash
# Clone/update bare mirrors for each submodule in .gitmodules (relay catalog).
# Requires: git, .gitmodules at repo root (run from relay-master checkout).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .gitmodules ]]; then
  echo "sync-relay-catalog: no .gitmodules in $ROOT" >&2
  exit 1
fi

RELAY_REPO_PATH="${RELAY_REPO_PATH:-${RELAY_DATA:-/opt/relay/data}}"
EMIT_YAML=0
RELAY_SERVER_ID=""

usage() {
  echo "Usage: $0 [--emit-authorized-repos SERVER_ID]" >&2
  echo "  Writes authorized-repos YAML to stdout; per-repo branch comes from .gitmodules submodule.<name>.branch (default main)." >&2
  echo "  RELAY_REPO_PATH  destination for bare repos (default: /opt/relay/data)" >&2
  echo "  RELAY_DATA       used if RELAY_REPO_PATH is unset" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --emit-authorized-repos)
      EMIT_YAML=1
      shift
      RELAY_SERVER_ID="${1:-}"
      [[ -z "$RELAY_SERVER_ID" ]] && usage
      shift
      ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

mkdir -p "$RELAY_REPO_PATH"

list_submodule_names() {
  git config --file .gitmodules --name-only --get-regexp '^submodule\..*\.path$' \
    | sed -n 's/^submodule\.\(.*\)\.path$/\1/p' | sort -u
}

verify_root() {
  local bare_git_dir=$1
  local root_commit=$2
  local branch=$3
  local ref="refs/heads/${branch}"
  if ! git --git-dir="$bare_git_dir" rev-parse --verify "$ref" >/dev/null 2>&1; then
    echo "sync-relay-catalog: missing $ref in $bare_git_dir" >&2
    return 1
  fi
  if ! git --git-dir="$bare_git_dir" merge-base --is-ancestor "$root_commit" "$ref"; then
    echo "sync-relay-catalog: relayRootCommit $root_commit not ancestor of $ref (reject unrelated history)" >&2
    return 1
  fi
}

if [[ "$EMIT_YAML" -eq 1 ]]; then
  echo "relay_server_id: ${RELAY_SERVER_ID}"
  echo "repos:"
fi

while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  path=$(git config --file .gitmodules --get "submodule.${name}.path")
  url=$(git config --file .gitmodules --get "submodule.${name}.url")
  root=$(git config --file .gitmodules --get "submodule.${name}.relayRootCommit" 2>/dev/null || true)
  branch=$(git config --file .gitmodules --get "submodule.${name}.branch" 2>/dev/null || echo "main")

  if [[ -z "$path" || -z "$url" ]]; then
    echo "sync-relay-catalog: submodule '$name' missing path or url" >&2
    exit 1
  fi
  if [[ -z "$root" || ${#root} -ne 40 ]]; then
    echo "sync-relay-catalog: submodule '$name' needs submodule.${name}.relayRootCommit (40 hex chars)" >&2
    exit 1
  fi

  bare="${RELAY_REPO_PATH}/${name}.git"
  if [[ ! -d "$bare" ]]; then
    echo "sync-relay-catalog: cloning $name -> $bare"
    git clone --bare "$url" "$bare"
  else
    echo "sync-relay-catalog: fetching $name"
    git --git-dir="$bare" remote set-url origin "$url" 2>/dev/null || true
    git --git-dir="$bare" fetch origin "+refs/heads/*:refs/heads/*" --prune
  fi

  verify_root "$bare" "$root" "$branch"

  if [[ "$EMIT_YAML" -eq 1 ]]; then
    echo "  ${name}:"
    echo "    anchor_commit: \"${root}\""
    echo "    branch: ${branch}"
  fi
done < <(list_submodule_names)

echo "sync-relay-catalog: done (${RELAY_REPO_PATH})"

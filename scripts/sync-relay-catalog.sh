#!/usr/bin/env bash
# Clone/update bare mirrors for each submodule in .gitmodules (relay catalog).
# Also mirrors this repo to RELAY_REPO_PATH/relay-master.git when origin is set.
# Run from a relay-master checkout (repo root contains .gitmodules).
#
# Shallow forge mirrors (default): RELAY_CATALOG_CLONE_DEPTH=1 uses
#   git clone --bare --depth 1 <url>
# so public catalog repos can be README-only roots (see RELAY_TRUST_AND_BOOTSTRAP.md).
# If the forge branch has more than one commit, ensure depth reaches relayRootCommit
# or set RELAY_CATALOG_CLONE_DEPTH higher. After operators push full history to the
# bare on the node, fetches become full (non-shallow) automatically.
#
# RELAY_CATALOG_FETCH_DEPTH: when the bare is still shallow, pass --depth to fetch
#   (default: same as RELAY_CATALOG_CLONE_DEPTH). Set to 0 or empty for full fetch.
# RELAY_CATALOG_AUTO_DEEPEN: after a shallow clone, if relayRootCommit is missing from
#   the object database, run one fetch --deepen N (handles a few extra README commits
#   on the forge while keeping the initial clone small).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .gitmodules ]]; then
  echo "sync-relay-catalog: no .gitmodules in $ROOT" >&2
  exit 1
fi

RELAY_REPO_PATH="${RELAY_REPO_PATH:-${RELAY_DATA:-/opt/relay/data}}"
EMIT_YAML=0
WRITE_YAML_PATH=""
RELAY_SERVER_ID=""

usage() {
  echo "Usage:" >&2
  echo "  $0                                    # sync bare mirrors only" >&2
  echo "  $0 --emit-authorized-repos SERVER_ID # full YAML to stdout (relay-master + submodules)" >&2
  echo "  $0 --write-authorized-repos SERVER_ID PATH  # write full YAML to PATH (atomic replace)" >&2
  echo "  RELAY_REPO_PATH   bare repo directory (default: /opt/relay/data)" >&2
  echo "  RELAY_DATA        used if RELAY_REPO_PATH unset" >&2
  echo "  RELAY_MASTER_BRANCH  branch name for relay-master stanza if HEAD detached (default: main)" >&2
  echo "  RELAY_SKIP_RELAY_MASTER_BARE=1  skip mirroring relay-master.git under RELAY_REPO_PATH" >&2
  echo "  RELAY_CATALOG_CLONE_DEPTH   submodule initial bare clone depth (default: 1)" >&2
  echo "  RELAY_CATALOG_FETCH_DEPTH   fetch depth while bare is shallow (default: clone depth; 0 = full)" >&2
  echo "  RELAY_CATALOG_AUTO_DEEPEN   if shallow mirror lacks relayRootCommit, fetch --deepen (default: 256)" >&2
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
    --write-authorized-repos)
      EMIT_YAML=1
      shift
      RELAY_SERVER_ID="${1:-}"
      WRITE_YAML_PATH="${2:-}"
      [[ -z "$RELAY_SERVER_ID" || -z "$WRITE_YAML_PATH" ]] && usage
      shift 2
      ;;
    -h|--help) usage ;;
    *)
      echo "sync-relay-catalog: unknown option: $1" >&2
      usage
      ;;
  esac
done

mkdir -p "$RELAY_REPO_PATH"

list_submodule_names() {
  git config --file .gitmodules --name-only --get-regexp '^submodule\..*\.path$' \
    | sed -n 's/^submodule\.\(.*\)\.path$/\1/p' | sort -u
}

bare_is_shallow() {
  local bare_git_dir=$1
  [[ "$(git --git-dir="$bare_git_dir" rev-parse --is-shallow-repository 2>/dev/null || echo false)" == "true" ]]
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
  if ! git --git-dir="$bare_git_dir" cat-file -e "${root_commit}^{commit}" 2>/dev/null; then
    echo "sync-relay-catalog: relayRootCommit $root_commit not present in shallow mirror $bare_git_dir" >&2
    echo "sync-relay-catalog: increase RELAY_CATALOG_CLONE_DEPTH / RELAY_CATALOG_FETCH_DEPTH or unshallow the forge branch" >&2
    return 1
  fi
  if ! git --git-dir="$bare_git_dir" merge-base --is-ancestor "$root_commit" "$ref"; then
    echo "sync-relay-catalog: relayRootCommit $root_commit not ancestor of $ref (reject unrelated history)" >&2
    return 1
  fi
}

relay_master_branch_name() {
  local b
  b="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  if [[ "$b" == "HEAD" ]]; then
    echo "${RELAY_MASTER_BRANCH:-main}"
  else
    echo "$b"
  fi
}

sync_relay_master_mirror() {
  [[ "${RELAY_SKIP_RELAY_MASTER_BARE:-}" == "1" ]] && return 0
  local url dest
  url=$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)
  if [[ -z "$url" ]]; then
    echo "sync-relay-catalog: no remote.origin on catalog checkout; skipping relay-master.git mirror" >&2
    return 0
  fi
  dest="${RELAY_REPO_PATH}/relay-master.git"
  if [[ ! -d "$dest" ]]; then
    echo "sync-relay-catalog: mirroring relay-master -> $dest"
    git clone --mirror "$url" "$dest"
  else
    echo "sync-relay-catalog: fetching relay-master mirror"
    git --git-dir="$dest" remote set-url origin "$url" 2>/dev/null || true
    git --git-dir="$dest" fetch origin "+refs/*:refs/*" --prune
  fi
}

emit_full_authorized_repos() {
  local master_head master_branch bare
  master_head=$(git -C "$ROOT" rev-parse HEAD)
  master_branch=$(relay_master_branch_name)
  bare="${RELAY_REPO_PATH}/relay-master.git"

  echo "relay_server_id: ${RELAY_SERVER_ID}"
  echo "repos:"
  echo "  relay-master:"
  echo "    anchor_commit: \"${master_head}\""
  echo "    branch: ${master_branch}"

  if [[ -d "$bare" ]]; then
    if ! git --git-dir="$bare" rev-parse --verify "${master_head}^{commit}" >/dev/null 2>&1; then
      echo "sync-relay-catalog: warning: relay-master.git mirror missing commit ${master_head}" >&2
    elif ! git --git-dir="$bare" merge-base --is-ancestor "$master_head" "refs/heads/${master_branch}" 2>/dev/null; then
      echo "sync-relay-catalog: warning: ${master_head} not ancestor of refs/heads/${master_branch} on mirror" >&2
    fi
  fi

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    path=$(git config --file .gitmodules --get "submodule.${name}.path")
    root=$(git config --file .gitmodules --get "submodule.${name}.relayRootCommit" 2>/dev/null || true)
    branch=$(git config --file .gitmodules --get "submodule.${name}.branch" 2>/dev/null || echo "main")
    [[ -z "$path" || -z "$root" ]] && continue
    echo "  ${name}:"
    echo "    anchor_commit: \"${root}\""
    echo "    branch: ${branch}"
  done < <(list_submodule_names)
}

sync_relay_master_mirror

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
  clone_depth="${RELAY_CATALOG_CLONE_DEPTH:-1}"
  fetch_depth="${RELAY_CATALOG_FETCH_DEPTH:-${RELAY_CATALOG_CLONE_DEPTH:-1}}"

  if [[ ! -d "$bare" ]]; then
    echo "sync-relay-catalog: cloning $name -> $bare (depth=${clone_depth})"
    if [[ -n "$clone_depth" && "$clone_depth" != "0" ]]; then
      git clone --bare --depth "$clone_depth" "$url" "$bare"
    else
      git clone --bare "$url" "$bare"
    fi
  else
    echo "sync-relay-catalog: fetching $name"
    if git --git-dir="$bare" remote get-url origin >/dev/null 2>&1; then
      git --git-dir="$bare" remote set-url origin "$url"
    else
      git --git-dir="$bare" remote add origin "$url"
    fi
    if bare_is_shallow "$bare" && [[ -n "$fetch_depth" && "$fetch_depth" != "0" ]]; then
      git --git-dir="$bare" fetch origin "+refs/heads/*:refs/heads/*" --prune --depth "$fetch_depth"
    else
      git --git-dir="$bare" fetch origin "+refs/heads/*:refs/heads/*" --prune
    fi
  fi

  if ! verify_root "$bare" "$root" "$branch"; then
    if bare_is_shallow "$bare"; then
      echo "sync-relay-catalog: deepening shallow mirror for $name (reach relayRootCommit)..." >&2
      deepen="${RELAY_CATALOG_AUTO_DEEPEN:-256}"
      git --git-dir="$bare" fetch origin "+refs/heads/*:refs/heads/*" --prune --deepen="$deepen" || true
    fi
    verify_root "$bare" "$root" "$branch"
  fi
done < <(list_submodule_names)

if [[ "$EMIT_YAML" -eq 1 ]]; then
  tmp=""
  if [[ -n "$WRITE_YAML_PATH" ]]; then
    tmp=$(mktemp)
    emit_full_authorized_repos > "$tmp"
    install -m 0644 "$tmp" "$WRITE_YAML_PATH"
    rm -f "$tmp"
    echo "sync-relay-catalog: wrote $WRITE_YAML_PATH" >&2
  else
    emit_full_authorized_repos
  fi
fi

echo "sync-relay-catalog: done (${RELAY_REPO_PATH})"

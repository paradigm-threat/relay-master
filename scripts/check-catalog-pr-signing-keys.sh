#!/usr/bin/env bash
# Review aid: warn when catalog PR removes signing_keys without relay_root_commit change.
# Exit 0 always (warn only); forge branch protection + human approval are authoritative.
set -euo pipefail

BASE="${1:-origin/main}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! git -C "$ROOT" rev-parse --verify "$BASE" >/dev/null 2>&1; then
  echo "check-catalog-pr-signing-keys: base ref $BASE not found; skip" >&2
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "check-catalog-pr-signing-keys: jq required" >&2
  exit 0
fi

warn=0
while IFS= read -r -d '' f; do
  [[ "$f" == catalog/repos/*.json ]] || continue
  before=$(git -C "$ROOT" show "${BASE}:${f}" 2>/dev/null || echo "{}")
  after=$(cat "$ROOT/$f")
  b_root=$(echo "$before" | jq -r '.relay_root_commit // empty')
  a_root=$(echo "$after" | jq -r '.relay_root_commit // empty')
  b_keys=$(echo "$before" | jq -r '[.signing_keys[]?.public_key, .allowed_keys[]?] | map(select(. != "")) | .[]' 2>/dev/null | sort -u)
  a_keys=$(echo "$after" | jq -r '[.signing_keys[]?.public_key, .allowed_keys[]?] | map(select(. != "")) | .[]' 2>/dev/null | sort -u)
  removed=""
  for k in $b_keys; do
    if ! echo "$a_keys" | grep -qxF "$k"; then
      removed="${removed}  - ${k}"$'\n'
    fi
  done
  if [[ -n "$removed" ]]; then
    warn=1
    echo "WARN: $f removes signing key(s):" >&2
    echo -n "$removed" >&2
    if [[ "$b_root" == "$a_root" || -z "$a_root" ]]; then
      echo "  relay_root_commit unchanged — prefer disabling keys (status: disabled) unless bare history was reset." >&2
    else
      echo "  relay_root_commit changed ($b_root -> $a_root) — confirm history reset and security review." >&2
    fi
  fi
done < <(git -C "$ROOT" diff --name-only -z "$BASE" HEAD -- 'catalog/repos/*.json' 2>/dev/null || true)

if [[ "$warn" -eq 1 ]]; then
  echo "check-catalog-pr-signing-keys: review required (approval + signed commits with active keys)" >&2
fi
exit 0

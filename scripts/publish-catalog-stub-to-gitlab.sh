#!/usr/bin/env bash
# Create a GitLab project (if missing) and push a local stub repo (single-branch).
# Requires: GITLAB_TOKEN (personal/group access token with api scope), git, curl.
# Usage:
#   export GITLAB_TOKEN=...
#   ./scripts/publish-catalog-stub-to-gitlab.sh /path/to/stub GITLAB_GROUP_OR_NAMESPACE PROJECT_PATH_SLUG
# Example:
#   ./scripts/publish-catalog-stub-to-gitlab.sh ../snesology-library-catalog-stub clevertree snesology-library
set -euo pipefail

STUB="${1:-}"
NS="${2:-}"
SLUG="${3:-}"

if [[ -z "$STUB" || -z "$NS" || -z "$SLUG" || -z "${GITLAB_TOKEN:-}" ]]; then
  echo "Usage: GITLAB_TOKEN=... $0 STUB_DIR NAMESPACE PROJECT_SLUG" >&2
  echo "  NAMESPACE: group or username (e.g. clevertree)" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "This script requires jq (JSON for GitLab API)." >&2; exit 1; }

STUB="$(cd "$STUB" && pwd)"
if [[ ! -d "$STUB/.git" ]]; then
  echo "Not a git repo: $STUB" >&2
  exit 1
fi

GITLAB_HOST="${GITLAB_HOST:-gitlab.com}"
API="https://${GITLAB_HOST}/api/v4"
ENC_NS=$(printf '%s' "$NS" | jq -sRr @uri 2>/dev/null || python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$NS")
PROJECT_PATH="${NS}/${SLUG}"
ENC_PATH=$(printf '%s' "$PROJECT_PATH" | jq -sRr @uri 2>/dev/null || python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$PROJECT_PATH")

exists=$(curl -sS -o /dev/null -w "%{http_code}" \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${API}/projects/${ENC_PATH}")

if [[ "$exists" == "404" ]]; then
  echo "Creating GitLab project ${PROJECT_PATH}..." >&2
  gid=$(curl -sS -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" "${API}/groups/${ENC_NS}" | jq -r .id)
  if [[ -z "$gid" || "$gid" == "null" ]]; then
    gid=$(curl -sS -G -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      --data-urlencode "search=${NS}" \
      "${API}/namespaces" | jq -r --arg n "$NS" '.[] | select(.path==$n) | .id' | head -1)
  fi
  if [[ -z "$gid" || "$gid" == "null" ]]; then
    echo "Could not resolve namespace id for ${NS}; create the project in the UI or fix NAMESPACE" >&2
    exit 1
  fi
  curl -sS -f -X POST "${API}/projects" \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"${SLUG}\", \"path\": \"${SLUG}\", \"namespace_id\": ${gid}, \"visibility\": \"private\", \"initialize_with_readme\": false}" \
    | jq -r .http_url_to_repo >/dev/null
  echo "Created." >&2
elif [[ "$exists" == "200" ]]; then
  echo "Project ${PROJECT_PATH} already exists; pushing." >&2
else
  echo "GitLab API HTTP ${exists} for projects/${PROJECT_PATH}" >&2
  exit 1
fi

REMOTE_URL="https://oauth2:${GITLAB_TOKEN}@${GITLAB_HOST}/${PROJECT_PATH}.git"
if git -C "$STUB" remote get-url gitlab-publish >/dev/null 2>&1; then
  git -C "$STUB" remote set-url gitlab-publish "$REMOTE_URL"
else
  git -C "$STUB" remote add gitlab-publish "$REMOTE_URL"
fi

git -C "$STUB" push -u gitlab-publish main
echo "Pushed ${STUB} -> ${PROJECT_PATH}" >&2

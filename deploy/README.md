# relay-gateway deploy manifest (Helm-style)

**Normative doc:** [`relay-gateway/docs/RELAY_RECONCILE_PLAN.md`](../../relay-gateway/docs/RELAY_RECONCILE_PLAN.md)

| File | Purpose |
|------|---------|
| **`relay-gateway.json`** | Desired **relay-gateway** tarball: `git_tag`, `artifact_url`, `artifact_sha256`, optional `canary_hostname`, optional `reconcile_script`, optional `skip_binary_download`. |
| **`canary-complete.json`** | After the **canary** host succeeds, commit this so **fleet** nodes (non-canary) accept the same manifest. See example below. |

**Operators:** Fill `artifact_url` and `artifact_sha256` from your GitLab **generic package** (or other immutable HTTPS). Leave `artifact_sha256` empty to disable automatic binary reconcile until you are ready.

**Allowlist:** On each server, `/opt/relay/etc/reconcile-allowlist` lists `path<TAB>sha256` for any `reconcile_script` path. Compute SHA-256 with:

`git show HEAD:scripts/your-script.sh | sha256sum`

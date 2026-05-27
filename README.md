# relay-master

Canonical **catalog repository** for Relay deployments: it lists which Git repositories a relay node may mirror and serve, **where to clone them from**, and the **trusted root commit** for each. The same tree is the **default HTTP content** for the node apex when **`RELAY_DEFAULT_REPO=relay-master`** (or equivalent) is configured.

## relay-gateway version (Helm-style)

**[`deploy/`](./deploy/)** holds **`relay-gateway.json`** — desired **relay-gateway** install (Git tag, immutable tarball URL, SHA-256), optional **canary** hostname, and optional **`reconcile_script`**. Masters run **`/opt/relay/bin/relay-reconcile.sh`** on a timer when enabled in **`relay.env`**. This is **separate** from **`relay-catalog.json`** (which repos to mirror). Normative: **`relay-gateway/docs/RELAY_RECONCILE_PLAN.md`**.

## Whitelist = submodules

Each **[`git submodule`](https://git-scm.com/docs/git-submodules)** entry is one allowlisted repository:

| `.gitmodules` key | Role |
|-------------------|------|
| **`path`** | Superproject worktree path (e.g. `repos/paradigm-threat-files`). |
| **`url`** | **Authoritative clone source** for relays and operators (HTTPS or `git://` upstream). |
| **`branch`** | *(Optional.)* Hint for `git submodule update --remote`; relays still validate the recorded gitlink on update. |
| **`relayRootCommit`** | *(Relay-specific.)* Full **40-character** object id of the **trusted root** for this repository. Git ignores this key; Relay tooling uses it. After clone/fetch, that commit **must be an ancestor** of the configured branch tip (same rule as **`anchor_commit`** in generated **`authorized-repos.yaml`**). |

Adding a repository: **merge a change that adds the submodule** (path + url + `relayRootCommit`), then run **`scripts/sync-relay-catalog.sh`** on the server (or in CI) so bare mirrors exist under **`RELAY_REPO_PATH`**.

### Beyond a whitelist: what submodules are good for

Submodules are not *only* a policy list:

- **Reproducible pins:** the superproject commit records **exact submodule SHAs**, so “what the mesh should run” is reviewable in one diff.
- **`branch` + `update`:** standard Git workflows for tracking upstream without losing the pin until you commit an update.
- **Layout / tooling:** nested repos stay separate objects; CI can `submodule foreach` or skip paths with **`ignore`** / **`active`** flags.
- **Docs and scripts in-tree:** this repo carries **`scripts/sync-relay-catalog.sh`** next to the policy definition.

Relay-specific policy is the combination of **`url`** (source of truth for clone) + **`relayRootCommit`** (anti–unrelated-history).

### Public stub + private body (recommended for restricted content)

The forge **`url`** should normally reference a repository whose **first commit is minimal** (e.g. **README-only**). **`scripts/sync-relay-catalog.sh`** defaults to **`git clone --bare --depth 1`** (see **`RELAY_CATALOG_CLONE_DEPTH`**) so nodes pull almost nothing from GitLab/GitHub while **`relayRootCommit`** still pins the allowed root. **Bulk data and private history are not pushed to that forge URL**; operators **`git push`** the full mirror to **`git://<relay>:9418/<name>.git`** after the catalog has created the bare repo.

With **`RELAY_CATALOG_CLONE_DEPTH=1`**, the forge branch must expose **`relayRootCommit`** in that shallow slice (simplest: **one commit** on **`main`** = stub only). If you add more forge commits, increase depth or document **`RELAY_CATALOG_FETCH_DEPTH`**.

- **`scripts/init-minimal-public-catalog-repo.sh`** — create a README-only root commit and print **`relayRootCommit`**.
- **`scripts/publish-catalog-stub-to-gitlab.sh`** — optional GitLab project create + push (needs **`GITLAB_TOKEN`**).

## User-facing clone URLs (`git://relaygateway.net/<repo>.git`)

**Git’s native protocol has no HTTP-style redirects.** Publishing a single hostname is a **routing** concern:

- **DNS** (multiple A/AAAA records), **anycast**, or a **TCP/L4 load balancer** can send `git://relaygateway.net:9418/` to a chosen node.
- **Per-repo routing** (name → specific node) is **not** built into `git://`; implement at the edge (custom proxy, internal DNS names per node, or document that **`relaygateway.net` resolves to the current canonical node**).

Normative **documentation URL** for humans: **`git://relaygateway.net/<repo-name>.git`** (port **9418** unless documented otherwise). Operators map that hostname to infrastructure.

## Security (today vs planned)

- **Relay nodes:** **`git push git://…`** to **`main`** is governed by **`.relay.yaml`** (signed commits + **`allowedKeys`**). **`develop`** may allow unsigned commits per policy.
- **Forge (GitLab):** use branch protection and review as usual.

### Commit signing (local clone)

Store the **private** key under **`~/.ssh/`** (e.g. **`relay-catalog-signing-ed25519`**), **`ssh-add`** it, then in this repo:

```bash
git config gpg.format ssh
git config user.signingkey "$HOME/.ssh/relay-catalog-signing-ed25519.pub"
git config commit.gpgsign true
git config merge.gpgsign true
```

Ordinary commits and merges are **signed automatically**; use **`git commit --no-gpg-sign`** when policy allows unsigned (e.g. **`develop`**). Full detail: **`relay-gateway/docs/RELAY_MASTER_DEPLOY.md`**.

## Operator workflow

1. **Propose** a new submodule (PR): set **`url`**, **`path`**, and **`relayRootCommit`** (run `git rev-list --max-parents=0 <branch>` on the trusted clone; if multiple roots exist, pick the canonical root your policy requires and document it).
2. **Merge** to the tracked branch of **`relay-master`**.
3. On each relay node, after **pull of `relay-master`** (checkout must have **`remote.origin`** so **`relay-master.git`** is mirrored under **`RELAY_REPO_PATH`**), run as the user that owns **`RELAY_REPO_PATH`**:

```bash
RELAY_REPO_PATH=/opt/relay/data ./scripts/sync-relay-catalog.sh
./scripts/sync-relay-catalog.sh --write-authorized-repos relay-atlanta1 /opt/relay/authorized-repos.yaml
```

`--emit-authorized-repos SERVER_ID` prints the same YAML to stdout. **`RELAY_SKIP_RELAY_MASTER_BARE=1`** skips the **`relay-master.git`** mirror (e.g. local dev).

**`relay-gateway`** can read the catalog directly (**`RELAY_MASTER_CATALOG_PATH`**) — then **`--write-authorized-repos`** is unnecessary; still run **`sync-relay-catalog.sh`** (without emit) to refresh bare mirrors under **`RELAY_REPO_PATH`**.

**Add a repo (developer machine, needs forge access):** **`./scripts/add-catalog-submodule.sh snesology-library https://gitlab.com/clevertree/your-repo.git main`** — clones, computes **`relayRootCommit`**, runs **`git submodule add`**, then commit and push. For a **stub** remote, create it first with **`init-minimal-public-catalog-repo.sh`** + **`publish-catalog-stub-to-gitlab.sh`** (or push manually), then add the submodule from that URL.

To **register a submodule** whose objects only exist locally until you push the stub, clone via a **`file:`** / relative path once, then rewrite **`.gitmodules`** **`url`** to the HTTPS forge URL:  
`git -c protocol.file.allow=always submodule add --name REPO ../your-stub-checkout repos/REPO` then **`git config -f .gitmodules submodule.REPO.url https://…`** and **`git submodule sync`**.

Set **`RELAY_DEFAULT_REPO=relay-master`** so the node apex serves this repository’s default branch.

## Unified catalog (`catalog/`)

Per-repo policy lives under **`catalog/repos/<name>.json`** with a **`tier`**:

| Tier | Meaning |
|------|---------|
| **`primary`** | Mesh repos (lax Git rules, `publish_branch` usually `main`) |
| **`hosted`** | Home thin hosting (strict text-only, default `publish_branch` **`release`**) |

- **`catalog/policy-profiles.json`** — default limits and publish branch per tier.
- **`relay-catalog.json`** — legacy aggregate; regenerate with **`scripts/build-relay-catalog-json.sh`** after editing `catalog/repos/`.
- Gateway: **`RELAY_MASTER_CATALOG_PATH`** loads `catalog/repos/` when present ([`relay-gateway/docs/RELAY_CATALOG.md`](../relay-gateway/docs/RELAY_CATALOG.md)).

Submodules in **`.gitmodules`** remain the clone source during transition; catalog records duplicate **`forge_url`** + **`relay_root_commit`** for tooling.

## Files

- **`catalog/`** — Per-repo JSON records and policy profiles (see above).
- **`scripts/build-relay-catalog-json.sh`** — Build **`relay-catalog.json`** from **`catalog/repos/*.json`**.
- **`scripts/check-catalog-pr-signing-keys.sh`** — Warn when a PR removes signing keys without a history reset.
- **`scripts/sync-relay-catalog.sh`** — Mirror **`relay-master.git`**, **shallow** clone/fetch submodule bare repos (configurable), verify **`relayRootCommit`**, write full **`authorized-repos.yaml`**.
- **`scripts/add-catalog-submodule.sh`** — Helper to add a submodule + **`relayRootCommit`** from a fresh clone.
- **`scripts/init-minimal-public-catalog-repo.sh`** — README-only repo for public catalog **`url`**.
- **`scripts/publish-catalog-stub-to-gitlab.sh`** — Create GitLab project + push stub (**`GITLAB_TOKEN`**).

### Note: `paradigm-threat-files` and multiple roots

That upstream repository currently has **two root commits** in history merged together. **`relayRootCommit`** is set to the older initial commit (**`3228be89…`**); **`sync-relay-catalog.sh`** checks that this commit is an **ancestor** of **`main`**, which still pins the allowed lineage for unrelated-history attacks.

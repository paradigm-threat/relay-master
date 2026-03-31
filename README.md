# relay-master

Canonical **catalog repository** for Relay deployments: it lists which Git repositories a relay node may mirror and serve, **where to clone them from**, and the **trusted root commit** for each. The same tree is the **default HTTP content** for the node apex when **`RELAY_DEFAULT_REPO=relay-master`** (or equivalent) is configured.

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

## User-facing clone URLs (`git://relaygateway.net/<repo>.git`)

**Git’s native protocol has no HTTP-style redirects.** Publishing a single hostname is a **routing** concern:

- **DNS** (multiple A/AAAA records), **anycast**, or a **TCP/L4 load balancer** can send `git://relaygateway.net:9418/` to a chosen node.
- **Per-repo routing** (name → specific node) is **not** built into `git://`; implement at the edge (custom proxy, internal DNS names per node, or document that **`relaygateway.net` resolves to the current canonical node**).

Normative **documentation URL** for humans: **`git://relaygateway.net/<repo-name>.git`** (port **9418** unless documented otherwise). Operators map that hostname to infrastructure.

## Security (today vs planned)

- **Today:** No required commit signing on **`relay-master`**; protect the forge and merge path as you would any ops repo.
- **Planned:** Require **signed commits** (and/or signed tags) for all changes to **`relay-master`**, so arbitrary actors cannot extend the submodule whitelist without keys you trust.

## Operator workflow

1. **Propose** a new submodule (PR): set **`url`**, **`path`**, and **`relayRootCommit`** (run `git rev-list --max-parents=0 <branch>` on the trusted clone; if multiple roots exist, pick the canonical root your policy requires and document it).
2. **Merge** to the tracked branch of **`relay-master`**.
3. On each relay node, after **pull of `relay-master`** (checkout must have **`remote.origin`** so **`relay-master.git`** is mirrored under **`RELAY_REPO_PATH`**), run as the user that owns **`RELAY_REPO_PATH`**:

```bash
RELAY_REPO_PATH=/opt/relay/data ./scripts/sync-relay-catalog.sh
./scripts/sync-relay-catalog.sh --write-authorized-repos relay-atlanta1 /opt/relay/authorized-repos.yaml
```

`--emit-authorized-repos SERVER_ID` prints the same YAML to stdout. **`RELAY_SKIP_RELAY_MASTER_BARE=1`** skips the **`relay-master.git`** mirror (e.g. local dev).

**Add a repo (developer machine, needs forge access):** **`./scripts/add-catalog-submodule.sh snesology-library https://gitlab.com/clevertree/snesology-library.git main`** — clones, computes **`relayRootCommit`**, runs **`git submodule add`**, then commit and push.

Set **`RELAY_DEFAULT_REPO=relay-master`** so the node apex serves this repository’s default branch.

## Files

- **`scripts/sync-relay-catalog.sh`** — Mirror **`relay-master.git`**, clone/fetch submodule bare repos, verify **`relayRootCommit`**, write full **`authorized-repos.yaml`**.
- **`scripts/add-catalog-submodule.sh`** — Helper to add a submodule + **`relayRootCommit`** from a fresh clone.

### Note: `paradigm-threat-files` and multiple roots

That upstream repository currently has **two root commits** in history merged together. **`relayRootCommit`** is set to the older initial commit (**`3228be89…`**); **`sync-relay-catalog.sh`** checks that this commit is an **ancestor** of **`main`**, which still pins the allowed lineage for unrelated-history attacks.

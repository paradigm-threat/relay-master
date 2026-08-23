# Catalog agent instructions

Shared reference for all repos in **`relay-master/catalog/repos/`**. Each catalog repo also has its own root **`AGENTS.md`** — read that first when working in a specific checkout.

---

## Fleet publish pattern (iad1 publish origin)

Most catalog repos use **`publish_origin: iad1.relaygateway.net`**.

| Step | Action |
|------|--------|
| 1 | Checkout the catalog **`publish_branch`**. |
| 2 | **`git push iad1 HEAD:<branch>`** first — server **`update` hook** blocks until mesh peers match or **times out** (failed push = publish failed). |
| 3 | **`git push gitlab HEAD:<branch>`** (forge backup) after iad1 succeeds. |
| 4 | Report outcome: **success** if iad1 push exited 0; on failure read `remote: mesh sync failed:` stderr. |

**Mesh state on failure:** `/opt/relay/state/post_push_sync/<repo>.json` on iad1. Operator debug: `relay-push-and-wait.sh` or `POST /api/sync/mesh/<repo>`.

**Why iad1 before GitLab:** replica startup sync can pull GitLab while iad1 lags, putting **hkg1/sjc1 ahead of publish origin** until healed. See **paradigm-threat-files** [`docs/GIT_REMOTE_STRATEGY.md`](../../pt/paradigm-threat-files/docs/GIT_REMOTE_STRATEGY.md).

---

## Catalog repos

| Repo | Branch | Agent hub |
|------|--------|-----------|
| **paradigm-threat-files** | `main` | [`AGENTS.md`](../../pt/paradigm-threat-files/AGENTS.md) |
| **paradigm-threat-timeline** | `main` | [`AGENTS.md`](../../pt/paradigm-threat-timeline/AGENTS.md) |
| **paradigm-threat-web** | `release` | [`AGENTS.md`](../../pt/paradigm-threat-web/AGENTS.md) |
| **clevertree-site** | `release` | [`AGENTS.md`](../../clevertree-site/AGENTS.md) |
| **relay-web-assets** | `release` | [`AGENTS.md`](../relay-web-assets/AGENTS.md) |
| **ff-story** | `main` | [`AGENTS.md`](../../ff/ff-story/AGENTS.md) |
| **ff-teaser** | `main` | [`AGENTS.md`](../../ff/ff-teaser/AGENTS.md) |
| **snesology-library** | `main` | [`AGENTS.md`](../../songwalker/snesology-library/AGENTS.md) |
| **songwalker-library** | `main` | [`AGENTS.md`](../../songwalker/songwalker-library/AGENTS.md) |

---

## Cursor rules convention

Each catalog repo uses:

- **`.cursor/rules/agents.mdc`** — `alwaysApply: true`, points to root **`AGENTS.md`**
- **paradigm-threat-files** also has **`.cursor/rules/articles.mdc`** (`globs: **/*.md`) for reader-facing article voice

Retired: brand-prefixed **`paradigm-threat-*.mdc`** shards — consolidated into **`AGENTS.md`** + topic docs.

*Last updated: 2026-08-23*

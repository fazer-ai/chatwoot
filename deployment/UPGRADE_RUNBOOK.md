# Chatwoot Fork — Definitive Upgrade Runbook

> **Single source of truth for upgrading this fork.** Read ONLY this file.
> Every other `deployment/*.md` is historical and superseded. Do not read them
> unless this runbook explicitly points you there.
>
> This is version-agnostic: substitute the version tags below and follow the steps.

---

## 0. Facts you need before anything (no exploration required)

| Thing | Value |
|---|---|
| Fork repo | `lucouto/chatwoot.fazer.ai` (remote `origin`) |
| Upstream | `fazer-ai/chatwoot` (remote `upstream`) — source of `vX.Y.Z-fazer-ai.N` tags |
| OSS | `chatwoot/chatwoot` (remote `chatwoot`) |
| Image (built by us) | `ghcr.io/lucouto/chatwoot.fazer.ai:<tag>-ee` |
| Build workflow | `.github/workflows/publish_my_ee_docker.yml` — triggers on push of tag `v*`; builds multi-arch (amd64+arm64) with `CW_EDITION=ee`; appends `-ee` to the tag |
| Deploy platform | **Coolify** on host `vm-coolify-n8n` (ssh `azureuser@vm-coolify-n8n`) |
| **Live PROD DB container** | `postgres-f8kkkgcsko4sogs88k8c80ok` (Coolify project `f8kkkgcsko4sogs88k8c80ok`) |
| **STAGING DB container** | `postgres-vkg4sgcco4wg8os4sckws088` (separate Coolify project `vkg4...`) |
| Compose files (repo) | `docker-compose.production-<ver>.yaml`, `docker-compose.staging-<ver>.yaml` |
| Current prod version | **v4.14.2-fazer-ai.84-ee** (as of 2026-06-17) |

**Why we build our own image** (not fazer-ai's stock): we keep customizations.
As of v4.14.2 the only genuine in-image customization left is the **automation
custom-attribute filter operators (frontend)** — most others were upstreamed or
reverted (Azure OpenAI was abandoned entirely).

**The one patch NOT baked into the image** — must stay volume-mounted in every compose:
```
/opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb
  → /app/config/initializers/99_fix_pricing_plan_quantity.rb:ro   (Enterprise unlock)
```

---

## 1. Build & publish the new image

```bash
cd ~/Projets_apps_github/fork_chatwoot_fazer_ai

# Sync upstream and merge the target release tag into the upgrade branch
git fetch upstream --tags
git checkout -b upgrade-to-<ver>        # or reuse the existing upgrade branch
git merge <upstream-tag>                # e.g. v4.14.2-fazer-ai.84
# Resolve conflicts (historically only config/app.yml version line).
# Large upstream merges OOM-kill the husky/eslint pre-commit hook — use:
git commit --no-verify

# Tag + push to trigger the build (the `-ee` suffix is added by the workflow)
git tag v<ver>
git push origin upgrade-to-<ver> --tags
```

Verify the build before touching Coolify:
```bash
gh run list --repo lucouto/chatwoot.fazer.ai --workflow=publish_my_ee_docker.yml --limit 3
docker buildx imagetools inspect ghcr.io/lucouto/chatwoot.fazer.ai:v<ver>-ee
```
Both `linux/amd64` and `linux/arm64` must resolve before proceeding.
If the merge build fails on a transient `registry-1.docker.io context deadline exceeded`
(Buildx bootstrap), just re-run: `gh run rerun <run-id> --failed`.

---

## 2. ⚠️ ALWAYS migrate staging FIRST, incrementally

**This is the most important rule.** A **big-bang multi-version jump** (e.g. 4.10→4.14
in one shot) runs *all* migrations at once with the *final* code loaded. Early data
migrations that reference a model whose **enum/attribute is backed by a column added
by a *later* migration** crash:
```
Undeclared attribute type for enum '<x>' in <Model>
```
We hit this live on prod: migration `20260112092041` (RemoveCountryCodeFromConversationFilters)
loaded `CustomFilter` with `enum :visibility`, but the `visibility` column is added by a
*later* migration `20260510160215`.

**Avoid it by migrating staging incrementally through intermediate versions.** Staging
never hit the bug because it stepped through versions; prod jumped and broke.
If you must big-bang, see the fix in §6.

---

## 3. Deploy to Coolify (staging, then prod)

1. Coolify → the service → **Edit Compose File** → paste `docker-compose.<env>-<ver>.yaml`.
2. The only volume mount that survives besides `storage`/`assets` is the
   `99_fix_pricing_plan_quantity.rb` Enterprise-unlock patch (see §0). Remove any
   other historical patch mounts (`filter_service.rb`, `show.html.erb`, Azure
   `base_open_ai_service.rb` — that last one would *reintroduce* removed code).
3. **Save** → Coolify pulls the image and redeploys. The `rails` service runs
   `db:chatwoot_prepare` in its `post_start` hook, so migrations run automatically.

SMTP is env-var driven (Gmail, port 587 STARTTLS). Set in Coolify env vars, not compose:
```
SMTP_USERNAME, SMTP_PASSWORD, MAIL_SENDER   (SMTP_ADDRESS/SMTP_PORT default to gmail:587)
```
> Remove any leftover `SMTP_TLS` / `SMTP_SSL` env vars — wrong for port 587 STARTTLS.
> The Gmail app password is in git history → treat as compromised, **rotate it**.

---

## 4. Verify (run on the host)

```bash
RAILS=$(docker ps --format '{{.Names}}' | grep -E '^rails-f8kk' | head -1)   # prod; staging = rails-vkg4
docker exec "$RAILS" sh -c "grep -m1 'version:' /app/config/app.yml"          # => <ver>
docker exec "$RAILS" bundle exec rails runner "puts ChatwootApp.enterprise?"  # => true
docker exec "$RAILS" bundle exec rails db:migrate:status | grep -c down       # => 0
docker exec "$RAILS" ls -la /app/config/initializers/99_fix_pricing_plan_quantity.rb
curl -s -o /dev/null -w "HTTP %{http_code}\n" https://chatwoot.cheminneuf.community
```
> NOTE: in 4.14 `ChatwootApp.config[:version]` raises (`undefined method 'config'`).
> Use the `grep` on `config/app.yml` instead.

Also confirm in-app: **Super Admin → Instance Status** (version, git SHA, edition,
migrations completed, Baileys version). **Trust this over the Coolify badge** (see §7).

---

## 5. Back up prod DB BEFORE the prod deploy

```bash
PG=postgres-f8kkkgcsko4sogs88k8c80ok
docker exec "$PG" sh -c 'pg_dump -U "$POSTGRES_USER" -d chatwoot_production -F c' > ~/chatwoot_prod_<date>.dump
ls -lh ~/chatwoot_prod_<date>.dump   # expect ~140-150 MB, NOT 0 bytes
```
> Eval `$POSTGRES_USER` **inside the container** — the host shell has no
> `$SERVICE_USER_POSTGRES`. A 0-byte dump + `role "root" does not exist` means you
> ran it as the host user; re-run with the in-container env as above.

---

## 6. If the big-bang migration bug bites (§2)

Idempotent fix — pre-create the future column/index, mark the late migration applied,
then resume. Adapt the version/column to whatever the error names:
```bash
RAILS=rails-f8kkkgcsko4sogs88k8c80ok
docker exec "$RAILS" bundle exec rails runner "
c = ActiveRecord::Base.connection
c.execute(%q{ALTER TABLE custom_filters ADD COLUMN IF NOT EXISTS visibility integer NOT NULL DEFAULT 0})
c.execute(%q{CREATE INDEX IF NOT EXISTS index_custom_filters_on_account_type_visibility_user ON custom_filters (account_id, filter_type, visibility, user_id)})
c.execute(%q{INSERT INTO schema_migrations (version) VALUES ('20260510160215') ON CONFLICT DO NOTHING})"
docker exec "$RAILS" bundle exec rails db:migrate     # resumes; should finish all migrations
```
Then restart rails + sidekiq in Coolify.

---

## 7. Coolify "Degraded (unhealthy)" + ghost Postgres — IGNORE IT

The prod stack shows **two Postgres rows and a "Degraded" badge**. This is **cosmetic**.
- The deployed compose (`/data/coolify/services/f8kk.../docker-compose.yml`) has exactly
  ONE `postgres` service + ONE volume; `docker ps -a --filter ancestor=pgvector/pgvector:pg16`
  shows only the one live healthy container.
- The 2nd row is an orphaned Coolify metadata record from the old 4.10 stack — **no
  container, no volume behind it**. Restart and Edit-Compose→Save→Redeploy do NOT clear it.
- **Judge health by `docker ps` / Instance Status, never the badge.**
- Definitive fix (optional, needs a window): delete + recreate the Coolify *service* from
  the compose file — named volumes survive. Not worth it just for a badge.

**NEVER `docker volume rm` or `docker rm` a postgres container to "fix" the badge.**

---

## 8. Rollback

In Coolify set both `rails` and `sidekiq` back to the previous tag and redeploy:
```yaml
image: 'ghcr.io/lucouto/chatwoot.fazer.ai:<previous-ver>-ee'
```
Image rollback alone is normally enough (most migrations are additive). Restore from the
§5 dump only if a migration corrupted data.

---

## 9. After prod is verified

- Merge `upgrade-to-<ver>` → `main` and tag, so the main line matches production.
- Disable upstream's `Publish Chatwoot CE/EE` workflows on tag triggers (they fail
  noisily; only `publish_my_ee_docker.yml` is needed).
- Update the "Current prod version" row in §0 and the memory file
  `chatwoot-fork-upgrade-2026-06.md`.

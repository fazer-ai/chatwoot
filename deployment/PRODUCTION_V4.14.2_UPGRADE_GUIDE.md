# Production Upgrade Guide: v4.10.0-fazer-ai.16 → v4.14.2-fazer-ai.84-ee

## Overview

Upgrade **production** from `v4.10.0-fazer-ai.16-ee` to `v4.14.2-fazer-ai.84-ee` by
swapping the Coolify image — the same custom fork image already validated on staging
(branch `upgrade-to-v4.14.2`, commit `8fcbea1`).

**Image**: `ghcr.io/lucouto/chatwoot.fazer.ai:v4.14.2-fazer-ai.84-ee`
**DB**: `chatwoot_production`
**Compose**: `docker-compose.production-v4.14.2.yaml`
**Rollback tag**: `v4.10.0-fazer-ai.16-ee`

> ⚠️ **This is a much bigger jump than staging.** Staging ran only 2 migrations (it was
> already at `.78`). **Production will run all 54 migrations** spanning 4.10→4.14.2, in one
> go — including data backfills and destructive schema changes. Treat this as a
> maintenance-window deploy with a verified backup. The good news: these are the *same*
> migrations staging applied successfully (across its `.78` then `.84` deploys).

---

## STEP 0 — Azure OpenAI: RESOLVED (abandoned)

The old prod compose mounted a custom **Azure** `base_open_ai_service.rb` (commented "still
needed"). **Decision: Azure/Captain never worked and has been abandoned.** Therefore:

- The Azure mount is **intentionally removed** in `docker-compose.production-v4.14.2.yaml` —
  do **not** re-add it. (It's a 4.10-era patch; overlaying it on the 4.14 image would break
  Zeitwerk anyway.)
- Nothing to configure: no `CAPTAIN_OPEN_AI_ENDPOINT` Azure setup needed. Captain falls back
  to upstream's standard behavior (configurable later via `CAPTAIN_OPEN_AI_*` only if you ever
  wire a standard OpenAI key).
- (Optional cleanup) the abandoned Azure patch under `/opt/chatwoot-patches/enterprise/.../
  base_open_ai_service.rb` can be deleted from the host since nothing mounts it anymore.

No remaining blocker — production deploy is the same clean image swap as staging, with the
54-migration care below.

---

## Pre-Upgrade Checklist

- [x] **Step 0 resolved** — Azure abandoned, mount removed (nothing to configure)
- [ ] Staging has soaked 24–48h on `v4.14.2-fazer-ai.84-ee` with no issues
- [ ] **Full production DB backup taken and verified** (see Backup below) — mandatory
- [ ] Image manifest confirmed pullable (`docker buildx imagetools inspect …:v4.14.2-fazer-ai.84-ee`)
- [ ] `/opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb` present on prod host
- [ ] SMTP env vars set in Coolify (`SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_SENDER`) + password rotated
- [ ] Maintenance window scheduled + users notified (expect brief downtime during migrations)
- [ ] Confirm the currently-live tag for rollback (compose says `.15`; the live build is `.16` — use whatever is actually running)

## Backup (mandatory — this is your real rollback)

> ⚠️ **Pick the right container.** This host runs multiple Postgres instances, and the
> *staging* container holds an **empty leftover `chatwoot_production`**. Backing that up would
> produce a useless dump. The live production DB is `postgres-f8kkkgcsko4sogs88k8c80ok`
> (verify by data freshness, below). Also: `$SERVICE_USER_POSTGRES` is **not** set in the host
> shell — evaluate the user *inside* the container (`$POSTGRES_USER`).

```bash
# 1. Confirm which container holds the LIVE chatwoot_production (recent data, non-zero count):
for c in $(docker ps --format '{{.Names}}' | grep -i postgres); do
  echo "=== $c ==="
  docker exec "$c" sh -c 'psql -U "$POSTGRES_USER" -d chatwoot_production -tAc \
    "select now()-max(created_at) as age, count(*) as convos from conversations"' 2>/dev/null
done
# (the one with recent age + non-zero convos is live; the empty one is the staging leftover)

# 2. Dump it (user/db evaluated inside the container):
PG=postgres-f8kkkgcsko4sogs88k8c80ok        # <-- the confirmed-live container
docker exec "$PG" sh -c 'pg_dump -U "$POSTGRES_USER" -Fc chatwoot_production' \
  > ~/chatwoot_production_pre-v4.14.2_$(date +%Y%m%d_%H%M).dump
ls -lh ~/chatwoot_production_pre-v4.14.2_*.dump   # confirm a real size (MBs), not 0
```

(See also `deployment/MANUAL_BACKUP_PRODUCTION.md`.)

## 🔐 SMTP / email (required — set before deploy)

`docker-compose.production-v4.14.2.yaml` **parameterizes SMTP via env vars**, whereas the
old `PRODUCTION_COMPOSE_V4.10.0.yaml` had the credentials **hardcoded**. If you paste the new
compose without setting these on the production Coolify service, the app still boots but
**email breaks** (and an empty `MAIL_SENDER` can raise on send).

Set these as environment variables / secrets on the **production** Coolify service:

| Var | Value |
|---|---|
| `SMTP_USERNAME` | `chatwoot@cheminneuf.church` |
| `SMTP_PASSWORD` | the Gmail app password — **use a freshly rotated one** |
| `MAIL_SENDER` | `chatwoot@cheminneuf.church` |

These have safe built-in defaults and only need overriding if different:
`SMTP_ADDRESS` (`smtp.gmail.com`), `SMTP_PORT` (`587`), `SMTP_AUTHENTICATION` (`login`),
`SMTP_ENABLE_STARTTLS_AUTO` (`true`).

> ⚠️ **Rotate the password.** The old Gmail app password was hardcoded in
> `PRODUCTION_COMPOSE_V4.10.0.yaml` (committed to git history), so it must be considered
> compromised. Generate a new Gmail app password, set it as `SMTP_PASSWORD`, and revoke the old one.

Verify after deploy via the Step 4 "Email sends" check.

## Migration risk notes (54 migrations)

All validated on staging, but production data is larger/older — watch these in particular:

- **`enforce_contact_fk_on_conversations`** — adds a FK + backfills; can **fail if orphaned
  conversations** exist (contact_id with no matching contact). Pre-check below.
- **Destructive renames/drops** — `rename_conversation_type_to_group_type`,
  `drop_conversation_group_members`, `drop_channel_voice`. These are why **image-only
  rollback is NOT safe** (old code can't read the new schema).
- **Data backfills** — webhook secrets, agent_bot/channel API secrets, captain document sync,
  internal-chat default channels, several feature-flag repurposes. These take time on large
  tables.
- **Concurrent indexes** — a few `algorithm: :concurrently` indexes (won't block, but add time).

Pre-check for the FK migration — run directly against the **live production** DB (avoids
picking the wrong Rails/Postgres container):

```bash
docker exec postgres-f8kkkgcsko4sogs88k8c80ok sh -c \
  'psql -U "$POSTGRES_USER" -d chatwoot_production -tAc \
   "select count(*) from conversations c where not exists (select 1 from contacts ct where ct.id = c.contact_id)"'
# expect 0; if > 0, those orphaned conversations must be cleaned before the FK migration
```

## ⚠️ Known cross-version migration failure — apply this fix

On the 4.10→4.14 **big-bang** migrate, `db:chatwoot_prepare` (the `post_start` hook) **fails**
on the first data migration with:

```
== 20260112092041 RemoveCountryCodeFromConversationFilters: migrating
StandardError: Undeclared attribute type for enum 'visibility' in CustomFilter.
```

**Cause (not data corruption):** the early migration loads the **4.14 `CustomFilter` model**,
which declares `enum :visibility`. That column is only added by a *much later* migration
(`20260510160215`). Running all migrations at once with the final code → the enum has no
backing column yet. (Staging never hit this because it migrated *incrementally*, with older
code, when `20260112092041` ran.)

**Fix (run inside the running rails container, then resume):** pre-create the `visibility`
column + index exactly as `20260510160215` would, mark that migration applied, then continue.
Idempotent — safe to re-run.

```bash
docker exec rails-f8kkkgcsko4sogs88k8c80ok bundle exec rails runner "
c = ActiveRecord::Base.connection
c.execute(%q{ALTER TABLE custom_filters ADD COLUMN IF NOT EXISTS visibility integer NOT NULL DEFAULT 0})
c.execute(%q{CREATE INDEX IF NOT EXISTS index_custom_filters_on_account_type_visibility_user ON custom_filters (account_id, filter_type, visibility, user_id)})
c.execute(%q{INSERT INTO schema_migrations (version) VALUES ('20260510160215') ON CONFLICT DO NOTHING})
puts 'visibility column + index added; 20260510160215 marked applied'
"
docker exec rails-f8kkkgcsko4sogs88k8c80ok bundle exec rails db:migrate 2>&1 | tail -60
```

The remaining 50+ migrations (incl. `EnforceContactFkOnConversations`) then complete with no
further conflicts. **After they finish, redeploy/restart rails + sidekiq** so they load the
complete schema (they booted against the partial one during the failed hook).

> If a *different* "undeclared enum / missing column / uninitialized constant" appears, the
> big-bang has more ordering conflicts — prefer rolling back and migrating **incrementally**
> through intermediate fazer-ai versions instead of patching each one.

## Upgrade Steps

### 1. Update compose in Coolify
Paste `docker-compose.production-v4.14.2.yaml` (or, on the existing compose): set both
`rails` + `sidekiq` to `…:v4.14.2-fazer-ai.84-ee`, **remove** the `filter_service.rb`,
`show.html.erb`, and **Azure `base_open_ai_service.rb`** mounts, **keep** the
`99_fix_pricing_plan_quantity.rb` mount. Save → deploy.

### 2. Migrations run automatically (`post_start` → `db:chatwoot_prepare`)
Watch them — with 54 migrations this is the slow part:

```bash
RAILS=$(docker ps --format '{{.Names}}' | grep "v4.14.2-fazer-ai.84-ee" | grep rails | cut -f1 | head -1)
docker logs -f "$RAILS"     # watch for "migrated" lines and any failure
```

If `post_start` times out on a large DB, run migrations manually and watch to completion:

```bash
docker exec "$RAILS" bundle exec rails db:migrate
```

### 3. Verify

```bash
docker exec "$RAILS" bundle exec rails runner "puts ChatwootApp.config[:version]"    # 4.14.2-fazer-ai.84
docker exec "$RAILS" bundle exec rails runner "puts ChatwootApp.enterprise?"          # true
docker exec "$RAILS" bundle exec rails db:migrate:status | grep -c '^  up'            # all up, 0 down
docker logs "$RAILS" --tail 400 | grep -iE "zeitwerk|uninitialized constant|NameError" || echo "✅ clean boot"
curl -s -o /dev/null -w "HTTP %{http_code}\n" "$FRONTEND_URL"
```

### 4. Functional smoke test (production)
- [ ] Login + conversation list loads
- [ ] **WhatsApp / Baileys** inboxes reconnect, send + receive
- [ ] **Captain** loads without errors (Azure abandoned — standard upstream behavior)
- [ ] **Email** sends (confirms SMTP env vars)
- [ ] Enterprise features unlocked (the `99_fix_pricing_plan_quantity.rb` mount)
- [ ] Automation rules with custom-attribute conditions still evaluate

## Rollback (production — both steps required)

Because of the destructive migrations, **reverting the image alone is NOT enough** — the
4.10 code cannot run against the 4.14 schema. Full rollback:

1. In Coolify, set both services back to `ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.16-ee`
   (restore the previous compose; the Azure mount is abandoned and need not be re-added).
2. Restore the DB from the pre-upgrade dump (target the live production container; user
   evaluated inside it):
   ```bash
   PG=postgres-f8kkkgcsko4sogs88k8c80ok
   docker exec -i "$PG" sh -c 'pg_restore -U "$POSTGRES_USER" -d chatwoot_production --clean --if-exists' \
     < ~/chatwoot_production_pre-v4.14.2_YYYYMMDD_HHMM.dump
   ```
3. Redeploy and verify version is back to `4.10.0-fazer-ai.16`.

> Any data created between deploy and rollback is lost on restore — keep the maintenance
> window tight and decide go/no-go quickly.

## Post-Upgrade
- [ ] Monitor logs + Sidekiq queues 24–48h
- [ ] Confirm WhatsApp sessions stayed authenticated (Baileys)
- [ ] Update `PRODUCTION_CHANGELOG.md` / version docs
- [ ] (Cleanup) disable upstream Docker Hub publish workflows on tags; trim the redundant
      `OPERATOR_TYPES_3` automation customization

## Version Information

| | |
|---|---|
| Previous | `v4.10.0-fazer-ai.16-ee` |
| New | `v4.14.2-fazer-ai.84-ee` |
| Branch / commit | `upgrade-to-v4.14.2` / `8fcbea1` |
| Migrations applied | 54 (4.10 → 4.14.2) |
| Upgrade date | _[fill in]_ |
| Upgraded by | _[fill in]_ |

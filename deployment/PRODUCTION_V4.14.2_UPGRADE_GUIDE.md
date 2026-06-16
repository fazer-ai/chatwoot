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

```bash
PG=$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)
docker exec "$PG" pg_dump -U "$SERVICE_USER_POSTGRES" -Fc chatwoot_production \
  > ~/chatwoot_production_pre-v4.14.2_$(date +%Y%m%d_%H%M).dump
ls -lh ~/chatwoot_production_pre-v4.14.2_*.dump   # confirm non-zero size
```

(See also `deployment/MANUAL_BACKUP_PRODUCTION.md`.)

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

Optional pre-check for the FK migration:

```bash
RAILS=$(docker ps --format '{{.Names}}' | grep -i rails | head -1)
docker exec "$RAILS" bundle exec rails runner \
  "puts Conversation.where.not(contact_id: Contact.select(:id)).count"   # expect 0
```

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
2. Restore the DB from the pre-upgrade dump:
   ```bash
   PG=$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)
   docker exec -i "$PG" pg_restore -U "$SERVICE_USER_POSTGRES" -d chatwoot_production --clean --if-exists \
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

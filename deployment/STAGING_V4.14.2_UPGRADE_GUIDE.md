# Staging Upgrade Guide: v4.14.0-fazer-ai.78 → v4.14.2-fazer-ai.84-ee

## Overview

Upgrade staging from `v4.14.0-fazer-ai.78-ee` to `v4.14.2-fazer-ai.84-ee` by swapping
the Coolify image tag. This build is your **own custom fork image** (branch
`upgrade-to-v4.14.2`, merge commit `8fcbea1`), not fazer-ai's stock image.

**Source repo**: [lucouto/chatwoot.fazer.ai](https://github.com/lucouto/chatwoot.fazer.ai)
**Image**: `ghcr.io/lucouto/chatwoot.fazer.ai:v4.14.2-fazer-ai.84-ee`
**Upstream basis**: `fazer-ai/chatwoot` tag `v4.14.2-fazer-ai.84`
**Target environment**: Staging (Coolify)
**Ready-to-paste compose**: `docker-compose.staging-v4.14.2.yaml`

### ⚠️ Important change vs previous upgrades

Earlier staging ran fazer-ai's stock image with your customizations injected as
**volume-mounted patch files** under `/opt/chatwoot-patches/`. This image is different:
**your customizations are baked in**, so most of those mounts are now redundant — and
one is actively harmful. See the mount table below.

## Customization status in this image

| Customization | In this image? | Action |
|---|---|---|
| Automation filter ops — `automationHelper.js`, `operators.js` | ✅ Baked in | **Remove mount** |
| `filter_service.rb` (`is_present`/`is_not_present`) | ✅ Upstream now supports natively | **Remove mount** |
| `super_admin/settings/show.html.erb` | ✅ Now identical to upstream | **Remove mount** |
| Azure OpenAI `enterprise/.../llm/base_open_ai_service.rb` | ❌ Reverted (not wanted) | **Remove mount** — mounting it would reintroduce removed Azure code |
| Enterprise unlock `config/initializers/99_fix_pricing_plan_quantity.rb` | ❌ NOT in image | **Keep mount** |

> Only **one** patch mount survives: `99_fix_pricing_plan_quantity.rb`. Everything else
> is either baked in or intentionally gone.

## Pre-Upgrade Checklist

- [ ] Confirm the image build succeeded and the tag is published (see "Verify image exists")
- [ ] Clone production DB to staging if you want a production-like test (see `deployment/REPLICATE_PRODUCTION_TO_STAGING.md`)
- [ ] Confirm `/opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb` exists on the staging host
- [ ] Confirm staging env vars are set in Coolify (incl. SMTP — see Security note)
- [ ] Note the current image tag for rollback (`v4.14.0-fazer-ai.78-ee` or `main-ee`)

## Verify image exists

```bash
# Build run status
gh run list --repo lucouto/chatwoot.fazer.ai --workflow=publish_my_ee_docker.yml --limit 3

# Pullable manifest (multi-arch)?
docker buildx imagetools inspect ghcr.io/lucouto/chatwoot.fazer.ai:v4.14.2-fazer-ai.84-ee
```

Do not proceed until the manifest resolves for both `linux/amd64` and `linux/arm64`.

## Upgrade Steps

### Step 1 — Verify current staging state

```bash
STAGING_RAILS=$(docker ps --format "{{.Names}}\t{{.Image}}" | grep -i "rails" | grep -i "chatwoot.fazer.ai" | cut -f1 | head -1)
echo "Staging Rails container: ${STAGING_RAILS:-NOT FOUND}"
[ -n "$STAGING_RAILS" ] && docker exec "$STAGING_RAILS" bundle exec rails runner "puts ChatwootApp.config[:version]"

# The one patch file that must remain on the host:
test -f /opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb \
  && echo "✅ enterprise-unlock patch present" \
  || echo "⚠️  MISSING: 99_fix_pricing_plan_quantity.rb — Enterprise unlock will not apply"
```

### Step 2 — Update Docker Compose in Coolify

1. Open the staging Chatwoot service in Coolify → **Edit** the docker-compose.
2. Paste the contents of `docker-compose.staging-v4.14.2.yaml`, **or** make these edits to the existing compose:
   - Set the image on **both** `rails` and `sidekiq`:
     ```yaml
     image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.14.2-fazer-ai.84-ee'
     ```
   - **Delete** these volume mounts from both services (now baked in / unwanted):
     ```
     .../automationHelper.js   .../operators.js   .../filter_service.rb
     .../super_admin/settings/show.html.erb
     .../enterprise/app/services/llm/base_open_ai_service.rb   <-- Azure, must be removed
     ```
   - **Keep** the storage/assets volumes and the single patch mount:
     ```yaml
     - '/opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb:/app/config/initializers/99_fix_pricing_plan_quantity.rb:ro'
     ```
3. **Save** → Coolify pulls the new image and redeploys.

### Step 3 — Migrations

The `rails` service runs `db:chatwoot_prepare` in its `post_start` hook, so migrations
run automatically on redeploy. This upgrade adds **2 migrations**:

- `20260508000000_repurpose_channel_twitter_flag_for_conversation_unread_counts.rb`
- `20260525093000_change_captain_document_external_link_to_text.rb`

Verify:

```bash
NEW_RAILS=$(docker ps --format "{{.Names}}\t{{.Image}}" | grep "v4.14.2-fazer-ai.84-ee" | grep rails | cut -f1 | head -1)
docker exec "$NEW_RAILS" bundle exec rails db:migrate:status | tail -10
# Schema version should be 2026_05_25_093000
```

### Step 4 — Verify

```bash
NEW_RAILS=$(docker ps --format "{{.Names}}\t{{.Image}}" | grep "v4.14.2-fazer-ai.84-ee" | grep rails | cut -f1 | head -1)

# Version + edition
docker exec "$NEW_RAILS" bundle exec rails runner "puts ChatwootApp.config[:version]"   # => 4.14.2-fazer-ai.84
docker exec "$NEW_RAILS" bundle exec rails runner "puts ChatwootApp.enterprise?"          # => true

# Enterprise unlock patch is mounted
docker exec "$NEW_RAILS" ls -la /app/config/initializers/99_fix_pricing_plan_quantity.rb

# No Zeitwerk / boot errors
docker logs "$NEW_RAILS" --tail 400 | grep -iE "zeitwerk|uninitialized constant|NameError" || echo "✅ clean boot"

# Health
curl -s -o /dev/null -w "HTTP %{http_code}\n" "${FRONTEND_URL:-https://staging-chatwoot.cheminneuf.community}"
```

### Step 5 — Functional smoke test

- [ ] Log in
- [ ] **WhatsApp / Baileys**: inbox connects, send + receive a message
- [ ] **Captain** (AI) loads — verify migrated `captain_document` external links render
- [ ] **Automation filters**: Settings → Automations — custom `is_present` / `is_not_present`
      operators appear. (NOTE: upstream now ships these natively, so watch for **duplicate
      operators** in the dropdown — if duplicated, that's the signal to drop the baked-in
      frontend customization in a follow-up.)
- [ ] Enterprise features accessible (unlock patch working)
- [ ] Send a test email (confirms SMTP env vars)

## Rollback

In Coolify, set both services back to the prior tag and redeploy:

```yaml
image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.14.0-fazer-ai.78-ee'
```

If the 2 migrations need reverting (rare — both are low-risk):

```bash
PREV_RAILS=$(docker ps --format "{{.Names}}\t{{.Image}}" | grep "v4.14.0-fazer-ai.78" | grep rails | cut -f1 | head -1)
docker exec "$PREV_RAILS" bundle exec rails db:rollback STEP=2
```

> Restore from a DB backup only if a migration corrupts data. Both migrations here are
> additive/low-risk, so image rollback alone is normally sufficient.

## 🔐 Security note (do this)

`docker-compose.staging-complete.yaml` has **hardcoded SMTP credentials** committed to
the repo (Gmail app password). The new compose parameterizes them via env vars. Before/at
deploy:

1. Set `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_SENDER` (and optionally `SMTP_ADDRESS`,
   `SMTP_PORT`, etc.) as Coolify environment variables / secrets.
2. **Rotate** the exposed Gmail app password — it is in git history and must be considered compromised.

## Follow-ups (optional, not blocking)

- Consider **baking** `99_fix_pricing_plan_quantity.rb` into the fork so the last volume
  mount can be removed (fully self-contained image). It is currently untracked in the repo.
- The tag push also triggers upstream's `Publish Chatwoot CE/EE` workflows; disable those
  on tag triggers to save CI minutes (only `publish_my_ee_docker.yml` is needed).
- If the automation operators show as duplicates (Step 5), drop the frontend customization
  to fully match upstream.

## Version Information

| | |
|---|---|
| Previous | `v4.14.0-fazer-ai.78-ee` |
| New | `v4.14.2-fazer-ai.84-ee` |
| Branch / commit | `upgrade-to-v4.14.2` / `8fcbea1` |
| Upgrade date | _[fill in]_ |
| Upgraded by | _[fill in]_ |

## After staging is validated

Run the same image swap on **production** (back up the DB first; production rollback tag
is `v4.10.0-fazer-ai.16-ee`). Monitor staging 24–48h before promoting.

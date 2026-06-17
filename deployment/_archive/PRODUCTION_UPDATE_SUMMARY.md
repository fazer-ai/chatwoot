# Production Update Summary: v4.10.0-fazer-ai.15-ee

## Quick Reference

**Current Production:** `v4.9.1-fazer-ai.2-ee`  
**Target Production:** `v4.10.0-fazer-ai.15-ee`  
**Image:** `ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee`  
**Status:** ✅ Ready for deployment

---

## What Was Fixed

1. **Bundle install retry logic** - Handles network timeouts
2. **Bundler version** - Pinned to 2.5.11 (matching Gemfile.lock)
3. **Tag pointing** - Updated to include all fixes

---

## Deployment Steps

### 1. Backup Database
```bash
pg_dump -h $POSTGRES_HOST -U $POSTGRES_USER -d chatwoot_production > backup_$(date +%Y%m%d).sql
```

### 2. Update Docker Compose
```yaml
rails:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee'
  
sidekiq:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee'
```

**Remove JavaScript volume mounts** (now baked into image):
- `automationHelper.js`
- `operators.js`

**Keep Ruby volume mounts:**
- `filter_service.rb`
- `99_fix_pricing_plan_quantity.rb`
- `show.html.erb`

### 3. Deploy
```bash
docker-compose pull
docker-compose up -d
docker-compose exec rails bundle exec rails db:migrate RAILS_ENV=production
```

### 4. Verify
```bash
# Check version
docker exec <rails> bundle exec rails runner "puts ChatwootApp.config.version"

# Test automation filters
# Go to Settings → Automations → Verify "Contains" and "Does not contain" operators
```

---

## Rollback

```yaml
# Revert to:
image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee'
```

Then restart services.

---

## Key Files

- **Full Guide:** `deployment/PRODUCTION_V4.10.0_UPGRADE_GUIDE.md`
- **Build Fixes:** `deployment/BUNDLER_VERSION_FIX.md`
- **Customizations:** `deployment/CUSTOM_AUTOMATION_FILTERS_SUMMARY.md`
- **Staging Compose:** `deployment/STAGING_COMPOSE_V4.10.0_CUSTOM.yaml`

---

**Ready to deploy!** ✅

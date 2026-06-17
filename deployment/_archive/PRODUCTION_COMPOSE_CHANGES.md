# Production Compose File Changes: v4.8.0 → v4.10.0

## Summary of Changes

**From:** `ghcr.io/lucouto/chatwoot.fazer.ai:main-ee` (v4.8.0-fazer-ai.5)  
**To:** `ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee`

---

## Changes Made

### 1. Image Tags Updated

**Rails Service:**
```yaml
# Before:
image: 'ghcr.io/lucouto/chatwoot.fazer.ai:main-ee'

# After:
image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee'
```

**Sidekiq Service:**
```yaml
# Before:
image: 'ghcr.io/lucouto/chatwoot.fazer.ai:main-ee'

# After:
image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee'
```

### 2. Volume Mounts Added

**Rails Service - Added:**
```yaml
# Automation filter customizations (baked into image, but kept for flexibility)
- '/opt/chatwoot-patches/app/services/filter_service.rb:/app/app/services/filter_service.rb:ro'
- '/opt/chatwoot-patches/app/views/super_admin/settings/show.html.erb:/app/app/views/super_admin/settings/show.html.erb:ro'
- '/opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb:/app/config/initializers/99_fix_pricing_plan_quantity.rb:ro'
```

**Rails Service - Kept:**
```yaml
# Azure OpenAI customization (still needed)
- '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'
```

**Sidekiq Service - Added:**
```yaml
# Automation filter customizations
- '/opt/chatwoot-patches/app/services/filter_service.rb:/app/app/services/filter_service.rb:ro'
- '/opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb:/app/config/initializers/99_fix_pricing_plan_quantity.rb:ro'
```

**Sidekiq Service - Kept:**
```yaml
# Azure OpenAI customization (still needed)
- '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'
```

**Note:** JavaScript files (`automationHelper.js`, `operators.js`) are **NOT** mounted because they're now baked into the compiled assets in the image.

### 3. Everything Else Unchanged

✅ All environment variables kept the same  
✅ All ports and healthchecks unchanged  
✅ Database, Redis, Baileys configurations unchanged  
✅ All other settings preserved

---

## What's Included in the New Image

The new image `v4.10.0-fazer-ai.15-ee` includes:

1. **Automation Filter Customizations** (baked into image):
   - "Contains" and "Does not contain" operators
   - Updated `automationHelper.js` with OPERATOR_TYPES_7
   - Updated `operators.js` with custom operators
   - All frontend assets pre-compiled

2. **Backend Customizations** (via volume mounts):
   - `filter_service.rb` - Case-insensitive text matching
   - `99_fix_pricing_plan_quantity.rb` - Pricing plan fix
   - `show.html.erb` - Super admin settings view

3. **Azure OpenAI** (via volume mount):
   - `base_open_ai_service.rb` - Azure OpenAI support

---

## Pre-Deployment Checklist

Before deploying, ensure these files exist on the production server:

```bash
# Automation filter customizations
/opt/chatwoot-patches/app/services/filter_service.rb
/opt/chatwoot-patches/app/views/super_admin/settings/show.html.erb
/opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb

# Azure OpenAI customization (should already exist)
/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb
```

**If files don't exist:**
1. Copy from staging server, OR
2. Copy from this repository:
   - `app/services/filter_service.rb`
   - `app/views/super_admin/settings/show.html.erb`
   - `config/initializers/99_fix_pricing_plan_quantity.rb`

---

## Deployment Steps

1. **Backup database** (critical!)
2. **Ensure patch files exist** on production server at `/opt/chatwoot-patches/`
3. **Update docker-compose file** with new image tag
4. **Pull new image:** `docker-compose pull`
5. **Restart services:** `docker-compose up -d`
6. **Run migrations:** `docker-compose exec rails bundle exec rails db:migrate RAILS_ENV=production`
7. **Verify deployment**

---

## Rollback

If you need to rollback, simply change the image tag back:

```yaml
image: 'ghcr.io/lucouto/chatwoot.fazer.ai:main-ee'
```

Then restart services.

---

## File Locations

- **New compose file:** `deployment/PRODUCTION_COMPOSE_V4.10.0.yaml`
- **Changes summary:** This file (`PRODUCTION_COMPOSE_CHANGES.md`)
- **Full upgrade guide:** `deployment/PRODUCTION_V4.10.0_UPGRADE_GUIDE.md`

# Production Deployment: Simple Steps

## Overview

**Main change:** Update the image tag in your docker-compose file  
**Additional steps:** Pull image, restart services, run migrations (if any)

---

## Step-by-Step

### Step 1: Backup Database (⚠️ CRITICAL - Do this first!)

```bash
# On production server
pg_dump -h localhost -U $SERVICE_USER_POSTGRES -d chatwoot_production > /tmp/chatwoot_backup_$(date +%Y%m%d_%H%M%S).sql

# Verify backup
ls -lh /tmp/chatwoot_backup_*.sql
```

### Step 2: Update Docker Compose File

**Change these 2 lines:**

**Before:**
```yaml
rails:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:main-ee'
  
sidekiq:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:main-ee'
```

**After:**
```yaml
rails:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee'
  
sidekiq:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee'
```

**Also add these volume mounts to rails service:**
```yaml
volumes:
  - 'storage:/app/storage'
  - 'assets:/app/public/assets'
  - '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'
  # Add these 3 new ones:
  - '/opt/chatwoot-patches/app/services/filter_service.rb:/app/app/services/filter_service.rb:ro'
  - '/opt/chatwoot-patches/app/views/super_admin/settings/show.html.erb:/app/app/views/super_admin/settings/show.html.erb:ro'
  - '/opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb:/app/config/initializers/99_fix_pricing_plan_quantity.rb:ro'
```

**And add these volume mounts to sidekiq service:**
```yaml
volumes:
  - 'storage:/app/storage'
  - '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'
  # Add these 2 new ones:
  - '/opt/chatwoot-patches/app/services/filter_service.rb:/app/app/services/filter_service.rb:ro'
  - '/opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb:/app/config/initializers/99_fix_pricing_plan_quantity.rb:ro'
```

**OR:** Use the complete file: `deployment/PRODUCTION_COMPOSE_V4.10.0.yaml`

### Step 3: Pull New Image

```bash
docker-compose pull
# OR if using Coolify, it will pull automatically when you save the compose file
```

### Step 4: Restart Services

```bash
# If using docker-compose directly
docker-compose up -d

# OR if using Coolify
# Just save the compose file and click "Redeploy" in Coolify interface
```

### Step 5: Run Migrations (if any)

```bash
# Check if migrations are needed
docker-compose exec rails bundle exec rails db:migrate:status RAILS_ENV=production

# Run migrations
docker-compose exec rails bundle exec rails db:migrate RAILS_ENV=production
```

### Step 6: Verify

```bash
# Check version
docker-compose exec rails bundle exec rails runner "puts ChatwootApp.config.version"
# Should show: 4.10.0-fazer-ai.15

# Check image
docker ps --format "{{.Names}}\t{{.Image}}" | grep rails
# Should show: v4.10.0-fazer-ai.15-ee

# Test automation filters in UI
# Go to Settings → Automations → Verify "Contains" and "Does not contain" operators
```

---

## If Using Coolify

1. **Backup database** (via Coolify or manually)
2. **Edit compose file** in Coolify:
   - Change image tags
   - Add new volume mounts
3. **Save and redeploy** - Coolify will:
   - Pull new image
   - Restart containers
4. **Run migrations** (via Coolify terminal or SSH)
5. **Verify** deployment

---

## What's Actually Required

✅ **Update compose file** - Change image tags and add volume mounts  
✅ **Restart services** - So containers use new image  
⚠️ **Backup database** - Safety measure  
⚠️ **Run migrations** - Only if there are new migrations  

**That's it!** No code changes, no file copying (files already exist), just:
1. Update compose file
2. Redeploy
3. Migrate (if needed)

---

## Quick Commands Summary

```bash
# 1. Backup
pg_dump ... > /tmp/backup_$(date +%Y%m%d).sql

# 2. Update compose file (edit manually or use production compose file)

# 3. Pull & restart
docker-compose pull && docker-compose up -d

# 4. Migrate
docker-compose exec rails bundle exec rails db:migrate RAILS_ENV=production

# 5. Verify
docker-compose exec rails bundle exec rails runner "puts ChatwootApp.config.version"
```

---

**That's it!** It's mainly just updating the compose file and redeploying. ✅

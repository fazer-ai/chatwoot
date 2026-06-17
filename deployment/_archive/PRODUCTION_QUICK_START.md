# Production Update Quick Start

## Current State
- **Production:** `v4.8.0-fazer-ai.5` (`main-ee` tag)
- **Target:** `v4.10.0-fazer-ai.15-ee`
- **Status:** ✅ Ready to deploy

## Quick Deployment

### 1. Backup Database (CRITICAL!)
```bash
pg_dump -h $POSTGRES_HOST -U $POSTGRES_USER -d chatwoot_production > /tmp/backup_$(date +%Y%m%d_%H%M%S).sql
```

### 2. Verify Patch Files Exist
```bash
# Check if these files exist on production server:
ls -la /opt/chatwoot-patches/app/services/filter_service.rb
ls -la /opt/chatwoot-patches/app/views/super_admin/settings/show.html.erb
ls -la /opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb
ls -la /opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb

# If missing, copy from staging or this repository
```

### 3. Update Compose File
Replace your current docker-compose file with: `deployment/PRODUCTION_COMPOSE_V4.10.0.yaml`

**Key changes:**
- Image: `main-ee` → `v4.10.0-fazer-ai.15-ee`
- Added volume mounts for automation filters (Ruby files)
- Kept Azure OpenAI mount

### 4. Deploy
```bash
# Pull new image
docker-compose pull

# Restart services
docker-compose up -d

# Run migrations
docker-compose exec rails bundle exec rails db:migrate RAILS_ENV=production

# Verify
docker ps --format "{{.Names}}\t{{.Image}}"
docker-compose exec rails bundle exec rails runner "puts ChatwootApp.config.version"
```

### 5. Verify Features
- [ ] Login works
- [ ] Automation filters show "Contains" and "Does not contain" operators
- [ ] Can create automation rules with new operators
- [ ] No errors in logs

## Rollback
```yaml
# Change image back to:
image: 'ghcr.io/lucouto/chatwoot.fazer.ai:main-ee'
```
Then restart services.

---

**Full Documentation:**
- Complete guide: `deployment/PRODUCTION_V4.10.0_UPGRADE_GUIDE.md`
- Compose file: `deployment/PRODUCTION_COMPOSE_V4.10.0.yaml`
- Changes: `deployment/PRODUCTION_COMPOSE_CHANGES.md`

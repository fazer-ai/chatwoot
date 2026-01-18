# Production Upgrade Guide: v4.9.1 → v4.10.0-fazer-ai.15-ee

## Overview

This guide documents the complete process for upgrading production from `v4.9.1-fazer-ai.2-ee` to `v4.10.0-fazer-ai.15-ee`, including all fixes applied and lessons learned.

---

## ✅ Build Fixes Applied

### Issue 1: Bundle Install Exit Code 6
**Problem:** `bundle install` failing with exit code 6 (network timeouts)  
**Solution:** Added retry logic to Dockerfile:
```dockerfile
bundle install -j 4 -r 5 --verbose || (sleep 10 && bundle install -j 4 -r 5 --verbose) || (sleep 20 && bundle install -j 4 -r 5 --verbose || exit 1)
```

### Issue 2: Bundler Version Mismatch
**Problem:** Dockerfile installed bundler 4.0.4 (latest) instead of 2.5.11, causing stricter dependency resolution  
**Solution:** Fixed Dockerfile to install correct version:
```dockerfile
gem install bundler -v ${BUNDLER_VERSION}  # Instead of: gem install bundler
```

**Why v4.9.1 worked:** It used bundler 2.5.x which is more lenient with dependency resolution, allowing the `devise-secure_password` conflict to be resolved.

### Issue 3: Tag Pointing to Old Commit
**Problem:** Tag `v4.10.0-fazer-ai.15-ee` pointed to commit before fixes  
**Solution:** Recreated tag to point to HEAD with all fixes

---

## Custom Image Build

### Image Details
- **Repository:** `ghcr.io/lucouto/chatwoot.fazer.ai`
- **Tag:** `v4.10.0-fazer-ai.15-ee`
- **Workflow:** `.github/workflows/build_custom_ee_image.yml`
- **Trigger:** Git tag `v4.10.0-fazer-ai.15-ee`

### What's Included in the Image
- ✅ Custom automation filters ("Contains", "Does not contain" operators)
- ✅ Updated `filter_service.rb` for case-insensitive text matching
- ✅ Updated `automationHelper.js` with OPERATOR_TYPES_7
- ✅ Updated `operators.js` with custom operators
- ✅ All frontend assets pre-compiled
- ✅ Enterprise Edition enabled

### Build Process
1. Push tag: `git tag -f v4.10.0-fazer-ai.15-ee && git push origin v4.10.0-fazer-ai.15-ee --force`
2. Workflow triggers automatically
3. Builds for both platforms: linux/amd64 and linux/arm64
4. Creates multi-arch manifest
5. Pushes to GitHub Container Registry

---

## Pre-Production Checklist

### 1. Verify Image Availability
```bash
# Check image exists
docker manifest inspect ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee

# Verify platforms
docker buildx imagetools inspect ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee
```

### 2. Backup Production Database
```bash
# Connect to production server
# Backup database (adjust connection details)
pg_dump -h $POSTGRES_HOST -U $POSTGRES_USER -d chatwoot_production > /tmp/chatwoot_prod_backup_$(date +%Y%m%d_%H%M%S).sql

# Verify backup
ls -lh /tmp/chatwoot_prod_backup_*.sql
```

### 3. Test in Staging First
- ✅ Staging should already be running v4.10.0-fazer-ai.15-ee
- ✅ Verify all customizations work
- ✅ Test automation filters with "Contains" and "Does not contain"
- ✅ Verify no regressions

### 4. Verify Current Production State
```bash
# Check current version in production
docker exec <rails-container> bundle exec rails runner "puts ChatwootApp.config.version"

# Check current image
docker ps --format "{{.Names}}\t{{.Image}}" | grep rails

# Should show: ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee
```

---

## Production Deployment Steps

### Step 1: Update Docker Compose File

**File:** Production docker-compose file (in Coolify or on server)

**Changes needed:**
```yaml
services:
  rails:
    image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee'  # Updated
    pull_policy: if_not_present
    volumes:
      - 'storage:/app/storage'
      - 'assets:/app/public/assets'
      # JavaScript customizations are now baked into the image - remove these:
      # - '/opt/chatwoot-patches/app/javascript/dashboard/helper/automationHelper.js:...'  # REMOVE
      # - '/opt/chatwoot-patches/app/javascript/dashboard/routes/dashboard/settings/automation/operators.js:...'  # REMOVE
      # Keep Ruby customizations (if any):
      - '/opt/chatwoot-patches/app/services/filter_service.rb:/app/app/services/filter_service.rb:ro'
      - '/opt/chatwoot-patches/app/views/super_admin/settings/show.html.erb:/app/app/views/super_admin/settings/show.html.erb:ro'
      - '/opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb:/app/config/initializers/99_fix_pricing_plan_quantity.rb:ro'
    # ... rest of config

  sidekiq:
    image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee'  # Updated
    pull_policy: if_not_present
    volumes:
      - 'storage:/app/storage'
      # Keep Ruby customizations:
      - '/opt/chatwoot-patches/app/services/filter_service.rb:/app/app/services/filter_service.rb:ro'
      - '/opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb:/app/config/initializers/99_fix_pricing_plan_quantity.rb:ro'
    # ... rest of config
```

**Key Changes:**
- ✅ Update image tag to `v4.10.0-fazer-ai.15-ee`
- ✅ Remove JavaScript volume mounts (now baked into image)
- ✅ Keep Ruby volume mounts (for runtime updates if needed)

### Step 2: Pull New Image
```bash
# On production server
docker pull ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee

# Verify image pulled
docker images | grep v4.10.0-fazer-ai.15-ee
```

### Step 3: Stop Services (Minimal Downtime)
```bash
# If using docker-compose
docker-compose stop rails sidekiq

# Or stop individual containers
docker stop <rails-container> <sidekiq-container>
```

### Step 4: Update and Start
```bash
# Update docker-compose (if using)
docker-compose up -d rails sidekiq

# Or restart with new image
docker-compose restart rails sidekiq
```

### Step 5: Run Database Migrations
```bash
# Connect to rails container
docker exec -it <rails-container> bash

# Run migrations
bundle exec rails db:migrate RAILS_ENV=production

# If needed, check migration status
bundle exec rails db:migrate:status
```

### Step 6: Verify Deployment
```bash
# Check version
docker exec <rails-container> bundle exec rails runner "puts ChatwootApp.config.version"
# Should show: 4.10.0-fazer-ai.15

# Check image
docker ps --format "{{.Names}}\t{{.Image}}" | grep rails
# Should show: ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee

# Check logs
docker logs <rails-container> --tail 50
docker logs <sidekiq-container> --tail 50

# Health check
curl http://localhost:3000/api
```

---

## Post-Deployment Verification

### 1. Functional Checks

**Custom Automation Filters:**
- [ ] Go to Settings → Automations
- [ ] Create/edit an automation rule
- [ ] For text custom attributes, verify "Contains" and "Does not contain" operators are available
- [ ] Test a rule with "Contains" operator
- [ ] Test a rule with "Does not contain" operator
- [ ] Verify rules execute correctly

**Application Health:**
- [ ] Login works
- [ ] Conversations load
- [ ] Messages send/receive
- [ ] Sidekiq jobs process
- [ ] No errors in logs

### 2. Version Verification
```ruby
# In Rails console
ChatwootApp.config.version  # Should be: "4.10.0-fazer-ai.15"
ChatwootApp.enterprise?     # Should be: true
```

### 3. Monitoring
- [ ] Check error logs for 30 minutes
- [ ] Monitor Sidekiq job queue
- [ ] Check application metrics
- [ ] Verify no increased error rates

---

## Rollback Procedure

If issues occur, rollback immediately:

### Quick Rollback
```bash
# Stop services
docker-compose stop rails sidekiq

# Revert docker-compose to previous image
# Change image back to: ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee

# Start services
docker-compose up -d rails sidekiq

# Verify rollback
docker ps --format "{{.Names}}\t{{.Image}}" | grep rails
docker exec <rails-container> bundle exec rails runner "puts ChatwootApp.config.version"
```

### Database Rollback (if migrations ran)
```bash
# Only if migrations were run and caused issues
docker exec -it <rails-container> bundle exec rails db:rollback STEP=1 RAILS_ENV=production

# Or rollback specific migration
bundle exec rails db:migrate:down VERSION=<migration_version> RAILS_ENV=production
```

---

## Differences from v4.9.1

### What Changed
1. **Base Chatwoot version:** 4.9.1 → 4.10.0
2. **Custom image build:** Includes automation filter customizations baked in
3. **Bundler version:** Explicitly pinned to 2.5.11
4. **Dockerfile retry logic:** Added for bundle install reliability

### What Stayed the Same
- Same Ruby version (3.4.4)
- Same dependencies (Rails 7.1.5.2)
- Same customizations (automation filters)
- Same volume mount strategy for Ruby files

---

## Troubleshooting

### Build Issues
- **Bundle install fails:** Check if bundler version is correct (2.5.11)
- **Dependency conflicts:** Ensure Gemfile.lock is up to date
- **Image not found:** Verify tag exists and is pushed

### Deployment Issues
- **Container won't start:** Check logs with `docker logs <container>`
- **Migrations fail:** Check database connectivity and permissions
- **Features missing:** Verify image includes customizations (check version)

### Runtime Issues
- **Operators missing:** Verify JavaScript assets are compiled (should be in image)
- **Sidekiq errors:** Check Sidekiq logs and job queue
- **Performance issues:** Monitor resource usage

---

## Contact & Support

- **Build logs:** GitHub Actions - https://github.com/lucouto/chatwoot.fazer.ai/actions
- **Image registry:** https://github.com/lucouto/chatwoot.fazer.ai/pkgs/container/chatwoot.fazer.ai
- **Customizations:** See `deployment/CUSTOM_AUTOMATION_FILTERS_SUMMARY.md`

---

## Summary

✅ **Image built successfully** with all customizations  
✅ **Bundler version fixed** (2.5.11 instead of 4.0.4)  
✅ **Retry logic added** for bundle install reliability  
✅ **Tag updated** to include all fixes  
✅ **Staging tested** and working  
✅ **Ready for production deployment**

**Next Steps:**
1. Complete pre-production checklist
2. Update production docker-compose
3. Deploy during maintenance window
4. Verify and monitor

---

**Last Updated:** 2026-01-18  
**Image Tag:** `v4.10.0-fazer-ai.15-ee`  
**Status:** ✅ Ready for Production

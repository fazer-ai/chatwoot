# Production Update Failure Analysis

Based on your current production configuration and documentation, here are the likely reasons why the last production update attempt failed.

## Current Production Configuration

Looking at `docker-compose.coolify.yaml`:
- ✅ Image: `ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee` (specific version)
- ✅ `pull_policy: if_not_present` (changed from `always` for stability)
- ✅ Post-start commands configured

## Likely Failure Reasons

### 1. **Pull Policy: `always` (Most Likely)**

**Problem:**
Your compose file shows `pull_policy: if_not_present` with a comment: `# Changed from 'always' for production stability`

This suggests the previous configuration had:
```yaml
pull_policy: always
```

**What happened:**
- `pull_policy: always` forces Docker to **always pull the latest image** on every restart/deploy
- Even with a specific version tag, if the image was updated/rebuild on the registry, it would pull the new build
- This could pull an **unexpected or broken version** of the same tag
- Or if you were using `latest-ee` or `main-ee`, it would pull whatever was latest

**Impact:**
- Unexpected changes in production
- Potential breaking changes
- No control over when updates happen
- Hard to rollback (don't know what version you had)

**Fix Applied:**
Changed to `pull_policy: if_not_present` - only pulls if image doesn't exist locally

### 2. **Using `latest-ee` or `main-ee` Tag**

**Problem:**
From `IMAGE_TAG_FIX.md` and `UPDATE_STRATEGY.md`, there were issues with:
- `latest-ee` tag not existing or not being published consistently
- Error: `no matching manifest for linux/amd64`

**What happened:**
- If you tried to use `latest-ee` or `main-ee` tag
- The tag might not exist in the registry
- Or it might be built for a different platform
- Deployment would fail with image pull errors

**Fix Applied:**
Switched to specific version tag: `v4.8.0-fazer-ai.5-ee`

### 3. **Migration Failures**

**Problem:**
Upgrading to a new version might have database migrations that:
- Failed to run
- Took too long (timeout)
- Had conflicts with existing data
- Required manual intervention

**Indicators:**
- Services restarting repeatedly
- Database connection errors
- Migration errors in logs

**How to Check:**
```bash
# Check migration status
docker exec <rails-container> bundle exec rails db:migrate:status

# Check for pending migrations
docker exec <rails-container> bundle exec rails db:migrate:status | grep "down"
```

### 4. **Image Pull Failures**

**Problem:**
- Network issues during image pull
- Registry authentication issues
- Image not available for your platform (linux/amd64)
- Registry rate limiting

**Indicators:**
- `Error response from daemon: pull access denied`
- `no matching manifest for linux/amd64`
- `network timeout`

### 5. **Post-Start Command Issues**

**Problem:**
Your production has:
```yaml
post_start:
  - command:
    - sh
    - '-c'
    - 'bundle exec rails db:chatwoot_prepare && bundle exec rails branding:update && if [ -n "${BRAND_ASSETS_URL}" ]; then deployment/extract_brand_assets.sh "${BRAND_ASSETS_URL}"; fi'
```

If `db:chatwoot_prepare` failed:
- Database migrations might have failed
- Service would keep restarting
- Health checks would fail

## Most Likely Scenario

Based on the evidence:

**Primary Issue: `pull_policy: always`**

1. You had `pull_policy: always` in production
2. On a restart/redeploy, it pulled a new version (even with same tag, or if using `latest-ee`)
3. The new version had issues (migrations, breaking changes, etc.)
4. Production failed
5. You changed to `pull_policy: if_not_present` to prevent this

**Secondary Issue: Tag Problems**

If you were using `latest-ee` or `main-ee`:
- Tag might not exist
- Or pulled a broken version
- Deployment failed

## How to Verify What Happened

### Check Production Logs

```bash
# In Coolify, check production Rails logs around the time of the failed update
# Look for:
# - Image pull errors
# - Migration errors
# - Startup failures
# - Database connection errors
```

### Check Image History

```bash
# See what images are available locally
docker images | grep chatwoot

# Check when images were pulled
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}" | grep chatwoot
```

### Check Migration Status

```bash
# In production Rails container
docker exec <rails-container> bundle exec rails db:migrate:status | tail -20

# Look for:
# - Pending migrations (down)
# - Failed migrations
# - Migration errors
```

## Prevention Measures (Already Applied)

✅ **1. Changed `pull_policy: if_not_present`**
- Prevents unexpected image pulls
- Only pulls if image doesn't exist locally
- More stable for production

✅ **2. Using specific version tag**
- `v4.8.0-fazer-ai.5-ee` instead of `latest-ee`
- Immutable - same tag = same image
- Easy to rollback

✅ **3. Staging environment**
- Test updates in staging first
- Validate before production

## Recommendations Going Forward

### 1. Always Test in Staging First

```bash
# Update staging to new version
# Test for 1+ weeks
# Then update production
```

### 2. Use Versioned Images

```yaml
# Good
image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'

# Bad
image: 'ghcr.io/fazer-ai/chatwoot:latest-ee'
image: 'ghcr.io/fazer-ai/chatwoot:main-ee'
```

### 3. Keep `pull_policy: if_not_present`

```yaml
# Current (Good)
pull_policy: if_not_present

# Avoid
pull_policy: always  # Too risky for production
```

### 4. Backup Before Updates

```bash
# Always backup before updating production
docker exec <postgres> pg_dump -U user chatwoot_production > backup_$(date +%Y%m%d).sql
```

### 5. Monitor After Updates

- Check logs for 24-48 hours after update
- Monitor error rates
- Verify all features work
- Check performance metrics

## Quick Diagnostic Commands

Run these to understand what happened:

```bash
# 1. Check current production version
docker exec $(docker ps --format '{{.Names}}' | grep -i rails | head -1) \
  bundle exec rails runner "puts Chatwoot.config[:version]"

# 2. Check migration status
docker exec $(docker ps --format '{{.Names}}' | grep -i rails | head -1) \
  bundle exec rails db:migrate:status | grep -E "down|up" | tail -10

# 3. Check for errors in logs (in Coolify)
# Go to Production → Logs → Look for errors around update time

# 4. Check image pull history
docker images ghcr.io/fazer-ai/chatwoot --format "table {{.Tag}}\t{{.CreatedAt}}\t{{.Size}}"
```

## Summary

**Most likely failure reason:**
1. `pull_policy: always` pulled an unexpected/broken version
2. Or using `latest-ee`/`main-ee` tag that had issues

**Fixes already applied:**
- ✅ Changed to `pull_policy: if_not_present`
- ✅ Using specific version tag
- ✅ Staging environment for testing

**Going forward:**
- Always test in staging first
- Use versioned images
- Keep `pull_policy: if_not_present`
- Backup before updates
- Monitor after deployments

Your current production configuration is now more stable and should prevent similar issues.





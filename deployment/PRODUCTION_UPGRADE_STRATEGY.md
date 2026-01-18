# Production Upgrade Strategy

A safe, step-by-step guide for upgrading production after staging validation.

## Prerequisites

Before upgrading production, ensure:

- [ ] **Staging validated for 1+ week** - No critical issues found
- [ ] **All features tested** - Everything works in staging
- [ ] **No errors in logs** - Staging logs are clean
- [ ] **Performance acceptable** - No degradation in staging
- [ ] **Migrations tested** - All database migrations completed successfully
- [ ] **Team notified** - Everyone aware of the upgrade

## Pre-Production Checklist

### 1. Verify Staging Status

```bash
# Check staging is running the new version
STAGING_RAILS=$(docker ps --format '{{.Names}}' | grep -i rails | grep -i staging | head -1)
docker exec $STAGING_RAILS bundle exec rails runner "puts Chatwoot.config[:version]"
# Should show: 4.9.0-fazer-ai.8

# Check for errors
docker logs $STAGING_RAILS --tail 100 | grep -i error
```

### 2. Create Production Backup

**Critical: Always backup before production upgrades!**

```bash
# On production server (via SSH)
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i postgres | grep -v staging | head -1)
DB_USER=$(docker exec $POSTGRES_CONTAINER printenv POSTGRES_USER)
BACKUP_FILE="/tmp/prod_backup_$(date +%Y%m%d_%H%M%S).sql"

# Create backup
docker exec $POSTGRES_CONTAINER pg_dump -U $DB_USER --no-owner --no-acl chatwoot_production > $BACKUP_FILE

# Verify backup size (should be > 0)
ls -lh $BACKUP_FILE

# Copy backup to safe location (optional)
# scp $BACKUP_FILE user@backup-server:/backups/
```

### 3. Document Current Production State

```bash
# Record current version
PROD_RAILS=$(docker ps --format '{{.Names}}' | grep -i rails | grep -v staging | head -1)
CURRENT_VERSION=$(docker exec $PROD_RAILS bundle exec rails runner "puts Chatwoot.config[:version]")
CURRENT_IMAGE=$(docker inspect $PROD_RAILS --format '{{.Config.Image}}')

echo "Current Production:"
echo "  Version: $CURRENT_VERSION"
echo "  Image: $CURRENT_IMAGE"
echo "  Backup: $BACKUP_FILE"
```

### 4. Prepare Rollback Plan

**Document rollback steps:**

```yaml
# Previous production image (for rollback)
rails:
  image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'  # Previous version
  pull_policy: if_not_present
sidekiq:
  image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'  # Previous version
  pull_policy: if_not_present
```

**Or if you have a previous fork version:**
```yaml
rails:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai-lc.5-ee'  # Previous fork version
```

## Production Upgrade Steps

### Step 1: Schedule Maintenance Window

- [ ] Choose low-traffic period
- [ ] Notify team/users (if applicable)
- [ ] Allocate 30-60 minutes for upgrade
- [ ] Have rollback plan ready

### Step 2: Update Production Compose File

In Coolify → Production Service:

```yaml
rails:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.0-fazer-ai-lc.8-ee'
  pull_policy: if_not_present
sidekiq:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.0-fazer-ai-lc.8-ee'
  pull_policy: if_not_present
```

**Double-check:**
- [ ] Using **Production** service (not staging!)
- [ ] Image tag is correct: `v4.9.0-fazer-ai-lc.8-ee`
- [ ] `pull_policy: if_not_present` (prevents unexpected pulls)

### Step 3: Deploy in Coolify

1. **Save the compose file**
2. **Click "Deploy"**
3. **Monitor deployment closely:**
   - Watch for errors
   - Check service health
   - Monitor logs

### Step 4: Verify Deployment

**Immediate checks (within 5 minutes):**

```bash
# Check services are running
docker ps | grep rails
docker ps | grep sidekiq

# Check version
PROD_RAILS=$(docker ps --format '{{.Names}}' | grep -i rails | grep -v staging | head -1)
docker exec $PROD_RAILS bundle exec rails runner "puts Chatwoot.config[:version]"
# Should show: 4.9.0-fazer-ai.8

# Check image
docker inspect $PROD_RAILS --format '{{.Config.Image}}'
# Should show: ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.0-fazer-ai-lc.8-ee

# Check for errors
docker logs $PROD_RAILS --tail 50 | grep -i error
```

**Migration check:**

```bash
# Check migration status
docker exec $PROD_RAILS bundle exec rails db:migrate:status | tail -10

# Should show no pending migrations (all "up")
```

**Health check:**

```bash
# Check health endpoint (in Coolify or via curl)
curl -I https://your-production-url.com/

# Should return: 200 OK
```

### Step 5: Functional Testing

Test critical features:

- [ ] **Login works** - Can log in to dashboard
- [ ] **Conversations load** - Can view conversations
- [ ] **Messages send** - Can send/receive messages
- [ ] **Settings accessible** - Can access settings page
- [ ] **Enterprise features** - All Enterprise features work
- [ ] **No errors in UI** - Check browser console

### Step 6: Monitor (24-48 hours)

**First hour:**
- [ ] Check logs every 15 minutes
- [ ] Monitor error rates
- [ ] Test critical features
- [ ] Check performance metrics

**First 24 hours:**
- [ ] Check logs every few hours
- [ ] Monitor for unusual errors
- [ ] Verify all features still work
- [ ] Check database performance

**48 hours:**
- [ ] Final verification
- [ ] Document any issues
- [ ] Mark upgrade as successful

## Rollback Procedure

**If anything goes wrong, rollback immediately:**

### Quick Rollback (< 5 minutes)

1. **In Coolify → Production Service:**
   - Edit docker-compose
   - Revert to previous image:
     ```yaml
     rails:
       image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'  # Previous
     sidekiq:
       image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'  # Previous
     ```
   - Save and redeploy

2. **Verify rollback:**
   ```bash
   docker exec $PROD_RAILS bundle exec rails runner "puts Chatwoot.config[:version]"
   # Should show previous version
   ```

### Full Rollback (If migrations ran)

If database migrations completed but you need to rollback:

1. **Stop services:**
   ```bash
   # In Coolify, stop production services
   ```

2. **Restore database:**
   ```bash
   POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i postgres | grep -v staging | head -1)
   DB_USER=$(docker exec $POSTGRES_CONTAINER printenv POSTGRES_USER)
   
   # Restore from backup
   docker exec -i $POSTGRES_CONTAINER psql -U $DB_USER chatwoot_production < $BACKUP_FILE
   ```

3. **Revert image** (as above)

4. **Restart services**

## Post-Upgrade Tasks

### 1. Update Documentation

- [ ] Update `deployment/PRODUCTION_CHANGELOG.md`
- [ ] Document any issues encountered
- [ ] Note any configuration changes

### 2. Clean Up

- [ ] Remove old backup files (after 30 days)
- [ ] Archive deployment logs
- [ ] Update runbooks if needed

### 3. Communication

- [ ] Notify team of successful upgrade
- [ ] Document any new features/improvements
- [ ] Share lessons learned

## Success Criteria

Upgrade is successful when:

- [ ] Services running stable for 48+ hours
- [ ] No critical errors in logs
- [ ] All features working correctly
- [ ] Performance acceptable
- [ ] No user complaints
- [ ] Database migrations completed
- [ ] Version displayed correctly

## Common Issues & Solutions

### Issue: Services won't start

**Solution:**
- Check logs: `docker logs <container>`
- Verify image exists: `docker manifest inspect <image>`
- Check environment variables
- Rollback if needed

### Issue: Migration fails

**Solution:**
- Check migration logs
- Verify database permissions
- Check disk space
- Rollback and investigate

### Issue: Performance degradation

**Solution:**
- Check resource usage
- Review slow queries
- Check for memory leaks
- Consider rollback if severe

### Issue: Features not working

**Solution:**
- Check logs for errors
- Verify configuration
- Test in staging first
- Rollback if critical

## Best Practices Summary

✅ **DO:**
- Always test in staging first (1+ week)
- Backup before every upgrade
- Use versioned tags (not `latest-ee`)
- Monitor closely after deployment
- Have rollback plan ready
- Deploy during low-traffic periods
- Document everything

❌ **DON'T:**
- Skip staging testing
- Deploy without backup
- Use `pull_policy: always` in production
- Deploy during peak hours
- Ignore errors
- Skip monitoring
- Deploy on Fridays (unless urgent)

## Quick Reference

**Current Production:**
```yaml
image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'
```

**Target Production:**
```yaml
image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.0-fazer-ai-lc.8-ee'
```

**Rollback:**
```yaml
image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'  # Previous
```

## Timeline Example

**Day 1-7:** Staging validation
- Deploy to staging
- Test thoroughly
- Monitor for issues

**Day 8:** Production upgrade preparation
- Create backup
- Schedule maintenance window
- Prepare rollback plan

**Day 9:** Production upgrade
- Deploy during maintenance window
- Verify immediately
- Monitor closely

**Day 9-11:** Post-upgrade monitoring
- Monitor for 48 hours
- Test all features
- Document any issues

**Day 11+:** Upgrade complete
- Mark as successful
- Update documentation
- Plan next upgrade





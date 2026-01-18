# Production Deployment Strategy

A safe, reliable approach to running and updating Chatwoot in production without breaking your environment.

## Core Principles

1. **Never deploy directly to production** - Always test in staging first
2. **Use versioned images** - Tag all production images with specific versions
3. **Immutable infrastructure** - Build customizations into images, not volume mounts
4. **Quick rollback capability** - Keep previous image versions available
5. **Staging mirrors production** - Test exact production configuration in staging first

## Recommended Architecture

```
┌─────────────────┐
│   Production    │
│  (Versioned)    │
│  v4.8.0-ee.5   │
└─────────────────┘
        ▲
        │ Tested & Validated
        │
┌─────────────────┐
│    Staging      │
│  (Testing)      │
│  main-ee        │
└─────────────────┘
        ▲
        │ Development
        │
┌─────────────────┐
│   Local Dev     │
│  (Your Fork)    │
└─────────────────┘
```

## Deployment Workflow

### Step 1: Develop & Test Locally

```bash
# Make changes in your fork
git checkout -b feature/my-change
# ... make changes ...
git commit -m "feat: add new feature"
git push origin feature/my-change
```

### Step 2: Test in Staging

```bash
# Deploy to staging using volume mounts (fast iteration)
./deployment/deploy_staging_customizations.sh coolify-vm

# Test thoroughly in staging:
# - All features work
# - No errors in logs
# - Performance is acceptable
# - No breaking changes
```

### Step 3: Build Production Image (After Staging Validation)

Only after staging is fully validated:

```bash
# Merge changes to main branch
git checkout main
git merge feature/my-change
git push origin main

# Build production image with version tag
# Example: v4.8.0-fazer-ai.6-ee
docker build -t ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.6-ee .
docker push ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.6-ee
```

### Step 4: Deploy to Production

```bash
# Update docker-compose.coolify.yaml
# Change image tag:
image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.6-ee'

# Deploy in Coolify (with rollback plan ready)
```

## Production Configuration Best Practices

### 1. Use Versioned Images (Current Approach - ✅ Good)

**Keep this approach!** It's the most reliable:

```yaml
# docker-compose.coolify.yaml
rails:
  image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'  # Specific version
  pull_policy: if_not_present  # Don't auto-update
```

**Benefits:**
- ✅ Immutable - image doesn't change
- ✅ Reproducible - same version = same behavior
- ✅ Rollback - just change image tag
- ✅ Tested - you tested this exact image in staging

### 2. Environment Variables for Secrets

**Current (Good):**
```yaml
SMTP_PASSWORD=${SERVICE_PASSWORD_SMTP}  # From Coolify env vars
```

**Never hardcode secrets in compose files!**

### 3. Health Checks

Your production already has health checks - keep them:

```yaml
healthcheck:
  test: ['CMD-SHELL', 'wget -qO- --header="Accept: text/html" http://127.0.0.1:3000/']
  interval: 60s
  timeout: 20s
  retries: 10
```

### 4. Post-Start Commands

Keep your production post-start commands:

```yaml
post_start:
  - command:
    - sh
    - '-c'
    - 'bundle exec rails db:chatwoot_prepare && bundle exec rails branding:update && if [ -n "${BRAND_ASSETS_URL}" ]; then deployment/extract_brand_assets.sh "${BRAND_ASSETS_URL}"; fi'
```

## Safe Update Process

### Pre-Deployment Checklist

Before updating production:

- [ ] **Staging tested** - All changes validated in staging for at least 1 week
- [ ] **No breaking changes** - Database migrations tested, no API changes
- [ ] **Backup created** - Database and volumes backed up
- [ ] **Rollback plan** - Previous image version documented
- [ ] **Monitoring ready** - Alerts configured, dashboards ready
- [ ] **Maintenance window** - Schedule during low-traffic period
- [ ] **Team notified** - Everyone aware of deployment

### Deployment Steps

1. **Create backup:**
   ```bash
   # Backup database
   ssh production-server "docker exec <postgres-container> pg_dump -U user chatwoot_production > backup_$(date +%Y%m%d).sql"
   ```

2. **Update image tag in compose file:**
   ```yaml
   image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.6-ee'  # New version
   ```

3. **Deploy in Coolify:**
   - Update docker-compose
   - Deploy service
   - Monitor logs closely

4. **Verify deployment:**
   - Check health endpoints
   - Test critical features
   - Monitor error rates
   - Check database migrations completed

5. **If issues occur:**
   - **Immediately rollback** to previous image version
   - Investigate in staging
   - Fix and retry

### Rollback Procedure

If something goes wrong:

```yaml
# In docker-compose.coolify.yaml, change back to previous version:
image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'  # Previous version
```

Then redeploy in Coolify. This is why versioned images are critical!

## Hybrid Approach: Image + Volume Mounts for Critical Fixes

For **emergency fixes only**, you can add volume mounts to production:

```yaml
volumes:
  - 'storage:/app/storage'
  # Emergency fix only - remove after next image build
  - '/opt/chatwoot-patches/config/initializers/99_fix_pricing_plan_quantity.rb:/app/config/initializers/99_fix_pricing_plan_quantity.rb:ro'
```

**Use this only for:**
- Critical security fixes
- Urgent bug fixes
- Temporary workarounds

**Then:**
1. Fix the issue properly in code
2. Build new image with fix
3. Remove volume mount
4. Deploy new image

## Recommended Production Setup

### Current Production (Good Foundation)

```yaml
# docker-compose.coolify.yaml
rails:
  image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'  # ✅ Versioned
  pull_policy: if_not_present  # ✅ Don't auto-update
  volumes:
    - 'storage:/app/storage'  # ✅ Only data volumes
  environment:
    - DEFAULT_LOCALE=pt_BR
    # ✅ Secrets via environment variables
  post_start:
    # ✅ Full setup including branding
  healthcheck:
    # ✅ Health monitoring
```

**Keep this approach!** It's production-ready.

### What to Add

1. **Version tagging strategy:**
   ```
   v4.8.0-fazer-ai.5-ee  # Current
   v4.8.0-fazer-ai.6-ee  # Next (after staging validation)
   v4.8.0-fazer-ai.7-ee  # Future
   ```

2. **Backup automation:**
   ```bash
   # Add to cron or Coolify scheduled tasks
   0 2 * * * /path/to/backup-script.sh
   ```

3. **Monitoring:**
   - Set up alerts for:
     - High error rates
     - Slow response times
     - Database connection issues
     - Disk space

4. **Documentation:**
   - Keep changelog of production versions
   - Document rollback procedures
   - Track what's tested in staging

## Staging → Production Promotion Process

### When Staging is Ready

1. **Staging validation period:** Minimum 1 week of stable operation
2. **Feature freeze:** No new changes during validation
3. **Load testing:** Test with production-like data volumes
4. **Security review:** Check for exposed secrets, vulnerabilities
5. **Documentation:** Update deployment docs with new version

### Build Production Image

```bash
# Tag with semantic version
git tag -a v4.8.0-fazer-ai.6-ee -m "Production release: Settings fix + automation filters"
git push origin v4.8.0-fazer-ai.6-ee

# Build and push
docker build -t ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.6-ee .
docker push ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.6-ee
```

### Deploy to Production

1. Update compose file with new version
2. Deploy during maintenance window
3. Monitor for 24-48 hours
4. If stable, mark as validated

## Emergency Fixes

For critical production issues that can't wait:

### Option 1: Hotfix Image (Recommended)

```bash
# Create hotfix branch
git checkout -b hotfix/critical-fix

# Make minimal fix
# ... fix code ...

# Build hotfix image
docker build -t ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-hotfix1-ee .
docker push ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-hotfix1-ee

# Deploy immediately
# Then merge to main and rebuild proper version
```

### Option 2: Volume Mount (Temporary)

Only if image rebuild takes too long:

```yaml
# Add temporary volume mount
volumes:
  - '/opt/chatwoot-patches/hotfix.rb:/app/lib/hotfix.rb:ro'
```

**Then immediately:**
1. Build proper image with fix
2. Remove volume mount
3. Deploy new image

## Monitoring & Alerts

Set up monitoring for:

1. **Application Health:**
   - Response times
   - Error rates
   - Request volumes

2. **Infrastructure:**
   - Container status
   - Resource usage (CPU, memory, disk)
   - Database connections

3. **Business Metrics:**
   - Active conversations
   - Message throughput
   - User activity

## Rollback Strategy

### Quick Rollback (< 5 minutes)

If deployment fails immediately:

1. Revert image tag in compose file
2. Redeploy in Coolify
3. Verify service restored

### Data Rollback (If migrations failed)

1. Stop services
2. Restore database from backup
3. Revert to previous image
4. Restart services

## Best Practices Summary

✅ **DO:**
- Use versioned images for production
- Test everything in staging first
- Keep backups before updates
- Monitor after deployments
- Document all changes
- Tag all production images
- Use environment variables for secrets

❌ **DON'T:**
- Deploy directly to production
- Use `latest` or `main` tags in production
- Hardcode secrets in compose files
- Skip staging testing
- Deploy during peak hours
- Ignore health checks
- Remove old image versions immediately

## Current Status Assessment

Your current production setup is **good**:

✅ Versioned images  
✅ Environment variables for secrets  
✅ Health checks configured  
✅ Post-start commands for full setup  
✅ Separate staging environment  

**Recommendations:**
1. Keep using versioned images (don't switch to volume mounts)
2. Always test in staging first (you're already doing this)
3. Add backup automation
4. Document rollback procedures
5. Set up monitoring/alerting

## Next Steps

1. **Document current production version** in a changelog
2. **Set up automated backups** (daily)
3. **Create rollback runbook** with exact steps
4. **Set up monitoring** for production
5. **Establish deployment schedule** (e.g., monthly updates)

Your production is already following best practices. The key is to **never skip staging validation** and **always have a rollback plan**.





# Production Deployment Checklist

## Pre-Deployment

- [ ] **Image verified** - Check image exists: `ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee`
- [ ] **Staging tested** - All customizations verified in staging environment
- [ ] **Backup created** - Production database backed up
- [ ] **Maintenance window** - Scheduled during low-traffic period
- [ ] **Team notified** - All stakeholders aware of deployment
- [ ] **Rollback plan** - Ready to revert if needed

## Deployment

- [ ] **Docker Compose updated** - Image tag changed to `v4.10.0-fazer-ai.15-ee`
- [ ] **Volume mounts updated** - JavaScript mounts removed, Ruby mounts kept
- [ ] **Image pulled** - `docker pull ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee`
- [ ] **Services stopped** - Rails and Sidekiq containers stopped
- [ ] **Services started** - New containers started with updated image
- [ ] **Migrations run** - `bundle exec rails db:migrate RAILS_ENV=production`
- [ ] **Health check** - Application responds correctly

## Post-Deployment Verification

### Immediate Checks (0-15 minutes)

- [ ] **Version correct** - `ChatwootApp.config.version` shows `4.10.0-fazer-ai.15`
- [ ] **Image correct** - `docker ps` shows `v4.10.0-fazer-ai.15-ee`
- [ ] **Application loads** - Login page accessible
- [ ] **Can login** - User authentication works
- [ ] **Conversations load** - Dashboard displays conversations
- [ ] **No errors in logs** - Check rails and sidekiq logs for errors

### Functional Checks (15-30 minutes)

- [ ] **Automation filters** - "Contains" and "Does not contain" operators visible
- [ ] **Automation rules** - Can create/edit rules with new operators
- [ ] **Rule execution** - Automation rules execute correctly
- [ ] **Messages send** - Can send messages in conversations
- [ ] **Messages receive** - Incoming messages processed
- [ ] **Sidekiq jobs** - Background jobs processing correctly

### Monitoring (30-60 minutes)

- [ ] **Error rate** - No increase in error rates
- [ ] **Response time** - Application performance normal
- [ ] **Sidekiq queue** - Job queue processing normally
- [ ] **Resource usage** - CPU/Memory usage normal
- [ ] **User reports** - No user-reported issues

## Rollback Criteria

Rollback immediately if:
- ❌ Application won't start
- ❌ Database migration fails critically
- ❌ Major functionality broken
- ❌ Error rate spikes significantly
- ❌ Data corruption detected

## Post-Deployment

- [ ] **Documentation updated** - Deployment recorded
- [ ] **Team notified** - Deployment successful
- [ ] **Monitoring** - Continue monitoring for 24 hours
- [ ] **Cleanup** - Remove old Docker images if space needed

---

## Quick Commands

### Check Current State
```bash
docker ps --format "{{.Names}}\t{{.Image}}"
docker exec <rails> bundle exec rails runner "puts ChatwootApp.config.version"
```

### View Logs
```bash
docker logs <rails-container> --tail 100 -f
docker logs <sidekiq-container> --tail 100 -f
```

### Health Check
```bash
curl http://localhost:3000/api
```

### Rollback
```bash
# Edit docker-compose to use: v4.9.1-fazer-ai.2-ee
docker-compose up -d
```

---

**Status:** Ready for deployment  
**Date:** _______________  
**Deployed by:** _______________  
**Verified by:** _______________

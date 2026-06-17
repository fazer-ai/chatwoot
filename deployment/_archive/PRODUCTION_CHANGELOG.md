# Production Deployment Changelog

Track all production deployments, versions, and changes.

## Current Production Version

**Version:** `v4.8.0-fazer-ai.5-ee`  
**Image:** `ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee`  
**Deployed:** (Date when deployed)  
**Status:** ✅ Stable

## Deployment History

### v4.8.0-fazer-ai.5-ee (Current)

**Deployed:** (Date)  
**Status:** ✅ Production

**Changes:**
- (List what's in this version)

**Staging Validation:**
- Tested in staging for: (duration)
- Issues found: None / (list issues)
- Performance: Good

**Rollback Plan:**
- Previous version: `v4.8.0-fazer-ai.4-ee` (if exists)
- Rollback command: Update image tag in `docker-compose.coolify.yaml`

---

### v4.8.0-fazer-ai.4-ee (Previous)

**Deployed:** (Date)  
**Status:** Replaced by v4.8.0-fazer-ai.5-ee

**Changes:**
- (List what was in this version)

---

## Upcoming Deployments

### v4.8.0-fazer-ai.6-ee (Planned)

**Status:** 🧪 Testing in Staging

**Planned Changes:**
- Settings page fix (pricing_plan_quantity type error)
- (Other changes)

**Staging Status:**
- Deployed to staging: (Date)
- Testing period: (Duration)
- Issues found: (List)
- Ready for production: ⏳ Pending validation

---

## Rollback Procedures

### Quick Rollback (< 5 minutes)

1. Open `docker-compose.coolify.yaml` in Coolify
2. Change image tag to previous version:
   ```yaml
   image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.4-ee'
   ```
3. Save and redeploy
4. Verify service restored

### Full Rollback (If database changes)

1. Stop all services
2. Restore database from backup
3. Update image tag to previous version
4. Restart services
5. Verify everything restored

---

## Notes

- Always test in staging for minimum 1 week before production
- Keep at least 2 previous image versions available
- Document all changes in this file
- Update status after each deployment





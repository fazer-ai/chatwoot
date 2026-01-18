# Production Database Backup Command

## ✅ Correct Backup Command (RECOMMENDED - Use This!)

```bash
docker exec postgres-f8kkkgcsko4sogs88k8c80ok \
  pg_dump -U 6IjRtavqqNlMy0Ad chatwoot_production \
  > /tmp/chatwoot_prod_$(date +%F_%H%M).sql
```

**This command:**
- Uses exact production container name: `postgres-f8kkkgcsko4sogs88k8c80ok`
- Uses exact production database user: `6IjRtavqqNlMy0Ad`
- Creates a backup file with timestamp
- **Produces correct backup size (~47MB for production)**

**Why this is better:**
- No risk of accidentally backing up staging
- No container auto-detection that might fail
- Guaranteed to backup production database

**Components:**
- Container: `postgres-f8kkkgcsko4sogs88k8c80ok` (production PostgreSQL container)
- User: `6IjRtavqqNlMy0Ad` (PostgreSQL username)
- Database: `chatwoot_production`
- Output: `/tmp/chatwoot_prod_YYYY-MM-DD_HHMM.sql`

## ⚠️ Alternative: Dynamic Version (Auto-detect Container)

**Not recommended** - Use the direct command above instead. This is only for reference if container names change in the future.

If container name might change, use:

```bash
# Find production PostgreSQL container by known suffix pattern
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}\t{{.Image}}' | grep postgres | grep "f8kkkgcsko4sogs88k8c80ok" | head -1 | cut -f1)

if [ -z "$POSTGRES_CONTAINER" ]; then
  echo "ERROR: Production container not found. Use direct command instead."
  exit 1
fi

# Verify it's production (not staging)
if [[ ! "$POSTGRES_CONTAINER" =~ "f8kkkgcsko4sogs88k8c80ok" ]]; then
  echo "ERROR: Wrong container detected. Use direct command instead."
  exit 1
fi

DB_USER=$(docker exec "$POSTGRES_CONTAINER" printenv POSTGRES_USER)
BACKUP_FILE="/tmp/chatwoot_prod_$(date +%F_%H%M).sql"

# Create backup
docker exec "$POSTGRES_CONTAINER" \
  pg_dump -U "$DB_USER" chatwoot_production \
  > "$BACKUP_FILE"

echo "Backup created: $BACKUP_FILE"
ls -lh "$BACKUP_FILE"
```

## Verification

After creating backup, verify it:

```bash
BACKUP_FILE="/tmp/chatwoot_prod_$(date +%F_%H%M).sql"

# Check file exists and size
ls -lh "$BACKUP_FILE"

# Check for table definitions (should be > 0)
grep -c "CREATE TABLE" "$BACKUP_FILE"

# Check for data (should be > 0)
grep -c "INSERT INTO\|COPY" "$BACKUP_FILE"

# View first few lines
head -30 "$BACKUP_FILE"
```

## Expected Backup Size

For a production Chatwoot database:
- **Small/new installation**: 1-10 MB
- **Medium installation**: 10-100 MB (your case: ~47MB is normal)
- **Large installation**: 100 MB - several GB

**If backup is suspiciously small (< 1MB or ~247K):**
1. ❌ You might be backing up STAGING instead of PRODUCTION
   - Staging container: `postgres-vkg4sgcco4wg8os4sckws088` → ~247K backup
   - Production container: `postgres-f8kkkgcsko4sogs88k8c80ok` → ~47MB backup
2. Verify correct database name was used
3. Verify backup completed without errors
4. **Solution: Use the direct command with exact container name**

## Restore Command

If you need to restore from backup:

```bash
POSTGRES_CONTAINER="postgres-f8kkkgcsko4sogs88k8c80ok"
DB_USER="6IjRtavqqNlMy0Ad"
BACKUP_FILE="/tmp/chatwoot_prod_2025-12-25_1928.sql"  # Use your actual backup file

# Restore
docker exec -i "$POSTGRES_CONTAINER" \
  psql -U "$DB_USER" chatwoot_production \
  < "$BACKUP_FILE"
```

## Notes

- Backups in `/tmp/` are temporary and may be deleted on reboot
- Consider copying backups to a persistent location
- Coolify may have built-in backup features - check if available
- Always verify backup contents before proceeding with upgrades


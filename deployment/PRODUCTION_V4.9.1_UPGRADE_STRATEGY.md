# Production Upgrade Strategy: v4.8.0-fazer-ai.5 → v4.9.1-fazer-ai.2-ee

Complete guide for upgrading production from v4.8.0-fazer-ai.5 to v4.9.1-fazer-ai.2-ee after successful staging validation.

## Overview

- **Current Production**: v4.8.0-fazer-ai.5 (`ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai.5-ee`)
- **Target Production**: v4.9.1-fazer-ai.2-ee (`ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee`)
- **Base**: Official Chatwoot v4.9.1 (hotfix for custom attributes display)
- **Customizations**: Custom automation filters + Enterprise unlock (built into image for production)
- **Staging Status**: ✅ **Successfully deployed and running** with `v4.9.1-fazer-ai.2-ee`

## Prerequisites

Before upgrading production, ensure:

- [ ] **Security review completed** - No credentials in compose file
- [ ] **Environment variables configured** - All sensitive data in Coolify Environment Variables

- [x] **Staging validated and deployed** - v4.9.1-fazer-ai.2-ee successfully running in staging ✅
- [ ] **No Zeitwerk errors in staging** - Verified staging logs are clean of autoloading errors
- [ ] **Enterprise modules load correctly in staging** - ChatwootApp.extensions returns ["enterprise"]
- [ ] **All features tested** - Everything works in staging
- [ ] **No critical errors in logs** - Staging logs are clean
- [ ] **Performance acceptable** - No degradation in staging
- [ ] **Migrations tested** - All database migrations completed successfully in staging
- [ ] **Team notified** - Everyone aware of the upgrade
- [ ] **Maintenance window scheduled** - Low-traffic period allocated (30-60 minutes)

## Pre-Production Checklist

### -1. Verify Staging (Zeitwerk Safety Check)

**Before upgrading production, confirm staging has NO Zeitwerk errors:**

```bash
# Find staging Rails container by image tag (most reliable method)
# Staging should be running v4.9.1-fazer-ai.2-ee
STAGING_RAILS=$(docker ps --format '{{.Names}}\t{{.Image}}' | grep "v4.9.1-fazer-ai.2-ee" | grep rails | cut -f1 | head -1)

# Alternative: If the above doesn't work, list all containers and identify manually:
# docker ps --format "table {{.Names}}\t{{.Image}}" | grep rails
# Look for the container with image: ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee

# Verify container was found
if [ -z "$STAGING_RAILS" ]; then
  echo "ERROR: Staging Rails container not found."
  echo "Expected image: ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee"
  echo "List all containers: docker ps --format 'table {{.Names}}\t{{.Image}}' | grep rails"
  exit 1
fi

echo "Using staging container: $STAGING_RAILS"

# Check staging logs for Zeitwerk errors
docker logs "$STAGING_RAILS" --tail 500 | grep -iE "zeitwerk|NameError|uninitialized constant|expected.*to.*be.*defined"
# Should return NO errors (empty output)

# Verify Enterprise modules loaded in staging
docker exec "$STAGING_RAILS" bundle exec rails runner "
  puts 'Staging Enterprise loaded: ' + ChatwootApp.enterprise?.to_s
  puts 'Staging Extensions: ' + ChatwootApp.extensions.inspect
  exit 0
"
# Should show: Staging Enterprise loaded: true, Staging Extensions: ["enterprise"]
```

**✅ If staging is clean, production should be safe.**
**❌ If staging has errors, DO NOT upgrade production until fixed.**

**Manual Identification (if needed):**
```bash
# List all running containers with their images
docker ps --format "table {{.Names}}\t{{.Image}}" | grep rails

# Identify staging by image tag: v4.9.1-fazer-ai.2-ee
# Identify production by image tag: main-ee (or v4.8.0-fazer-ai.5-ee)

# Then manually set the variable:
# STAGING_RAILS="rails-<hash>"
# PROD_RAILS="rails-<hash>"
```

### 0. Security Review

- [ ] Review current docker-compose for hardcoded credentials
- [ ] List all sensitive values that need to be moved to environment variables
- [ ] Prepare environment variable names and values
- [ ] Document which credentials are in use

### 1. Verify Staging Status

```bash
# Find staging Rails container by image tag (v4.9.1-fazer-ai.2-ee)
STAGING_RAILS=$(docker ps --format '{{.Names}}\t{{.Image}}' | grep "v4.9.1-fazer-ai.2-ee" | grep rails | cut -f1 | head -1)

# If not found, list all containers and identify manually:
# docker ps --format "table {{.Names}}\t{{.Image}}" | grep rails
# Look for container with image containing: v4.9.1-fazer-ai.2-ee

# Verify container was found
if [ -z "$STAGING_RAILS" ]; then
  echo "ERROR: Staging Rails container not found."
  echo "Expected image: ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee"
  echo "List all containers: docker ps --format 'table {{.Names}}\t{{.Image}}' | grep rails"
  exit 1
fi

echo "Using staging container: $STAGING_RAILS"

# Check staging is running the new version
docker exec "$STAGING_RAILS" bundle exec rails runner "puts Chatwoot.config[:version]"
# Should show: 4.9.1-fazer-ai.2 (or 4.9.1-fazer-ai.1 if config/app.yml wasn't updated)
# Note: Minor version string mismatch is acceptable, but Docker image tag is authoritative

# Verify staging image
docker inspect "$STAGING_RAILS" --format '{{.Config.Image}}'
# Should show: ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee

# Check for errors
docker logs "$STAGING_RAILS" --tail 100 | grep -i error

# Verify custom features work
# - Custom automation filters
# - Enterprise features
# - Custom attributes display (v4.9.1 fix)
```

### 2. Create Production Backup

**Critical: Always backup before production upgrades!**

**Recommended: Use exact container name (most reliable)**

```bash
# Direct command with known production container and user (RECOMMENDED)
docker exec postgres-f8kkkgcsko4sogs88k8c80ok \
  pg_dump -U 6IjRtavqqNlMy0Ad chatwoot_production \
  > /tmp/chatwoot_prod_$(date +%F_%H%M).sql

BACKUP_FILE="/tmp/chatwoot_prod_$(date +%F_%H%M).sql"
echo "Backup created: $BACKUP_FILE"
ls -lh "$BACKUP_FILE"
```

**Alternative: Auto-detect container (use with caution - verify correct container)**

```bash
# Find production PostgreSQL container
# Note: This method is less reliable - verify it finds the correct container!
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}\t{{.Image}}' | grep postgres | grep -E "f8kkkgcsko4sogs88k8c80ok" | head -1 | cut -f1)

if [ -z "$POSTGRES_CONTAINER" ]; then
  echo "ERROR: Production PostgreSQL container not found."
  echo "List all postgres containers:"
  docker ps --format "table {{.Names}}\t{{.Image}}" | grep postgres
  echo ""
  echo "Use the direct command instead:"
  echo "docker exec postgres-f8kkkgcsko4sogs88k8c80ok pg_dump -U 6IjRtavqqNlMy0Ad chatwoot_production > /tmp/chatwoot_prod_\$(date +%F_%H%M).sql"
  exit 1
fi

DB_USER=$(docker exec "$POSTGRES_CONTAINER" printenv POSTGRES_USER)
BACKUP_FILE="/tmp/chatwoot_prod_$(date +%F_%H%M).sql"

echo "Creating backup from container: $POSTGRES_CONTAINER"
echo "Database user: $DB_USER"
echo "Backup file: $BACKUP_FILE"

# Verify we have the correct container (production should have suffix f8kkkgcsko4sogs88k8c80ok)
if [[ ! "$POSTGRES_CONTAINER" =~ "f8kkkgcsko4sogs88k8c80ok" ]]; then
  echo "⚠️  WARNING: Container doesn't match production pattern!"
  echo "Expected: postgres-f8kkkgcsko4sogs88k8c80ok"
  echo "Found: $POSTGRES_CONTAINER"
  echo "Please use the direct command instead."
  exit 1
fi

# Create backup
docker exec "$POSTGRES_CONTAINER" \
  pg_dump -U "$DB_USER" chatwoot_production \
  > "$BACKUP_FILE"

# Verify backup was created
if [ ! -f "$BACKUP_FILE" ]; then
  echo "❌ ERROR: Backup file was not created!"
  exit 1
fi

# Verify backup size (should be > 0, typically several MB for production)
BACKUP_SIZE=$(stat -f%z "$BACKUP_FILE" 2>/dev/null || stat -c%s "$BACKUP_FILE" 2>/dev/null || echo 0)
BACKUP_SIZE_MB=$(echo "scale=2; $BACKUP_SIZE / 1024 / 1024" | bc 2>/dev/null || echo "unknown")
echo "Backup file size: $(ls -lh "$BACKUP_FILE" | awk '{print $5}') ($BACKUP_SIZE_MB MB)"

# ⚠️ IMPORTANT: Verify backup contains data
echo ""
echo "Verifying backup contents..."
# Check for table definitions
TABLE_DEFS=$(grep -c "CREATE TABLE" "$BACKUP_FILE" 2>/dev/null || echo 0)
if [ "$TABLE_DEFS" -gt 0 ]; then
  echo "✅ Backup contains $TABLE_DEFS table definitions"
else
  echo "❌ WARNING: No CREATE TABLE statements found in backup!"
fi

# Check for data
DATA_STATEMENTS=$(grep -c "INSERT INTO\|COPY" "$BACKUP_FILE" 2>/dev/null || echo 0)
if [ "$DATA_STATEMENTS" -gt 0 ]; then
  echo "✅ Backup contains data ($DATA_STATEMENTS INSERT/COPY statements)"
else
  echo "⚠️  WARNING: No data found in backup (no INSERT/COPY statements)!"
fi

# Expected size: Production databases are typically 1MB-100MB+ (not 247K)
# If backup is suspiciously small (< 1MB), verify:
if [ "$BACKUP_SIZE" -lt 1048576 ]; then  # Less than 1MB
  echo ""
  echo "⚠️  WARNING: Backup is smaller than 1MB. This might be staging, not production!"
  echo "Verify you're backing up the correct database:"
  echo "  - Production container should be: postgres-f8kkkgcsko4sogs88k8c80ok"
  echo "  - Staging container would be: postgres-vkg4sgcco4wg8os4sckws088"
  echo ""
  echo "If you see staging container name above, use the direct command:"
  echo "  docker exec postgres-f8kkkgcsko4sogs88k8c80ok pg_dump -U 6IjRtavqqNlMy0Ad chatwoot_production > /tmp/chatwoot_prod_\$(date +%F_%H%M).sql"
fi

# Copy backup to safe location (optional but recommended)
# scp $BACKUP_FILE user@backup-server:/backups/
```

**If backup verification fails or backup seems incomplete:**

Use the verification script to diagnose:
```bash
# Run the backup verification script
./deployment/VERIFY_BACKUP.sh

# Or manually check:
# 1. Verify database name is correct
docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -l

# 2. Check database size
docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d chatwoot_production -c "SELECT pg_size_pretty(pg_database_size('chatwoot_production'));"

# 3. Check table counts
docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d chatwoot_production -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';"

# 4. Check if data exists
docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d chatwoot_production -c "SELECT COUNT(*) FROM accounts;"
```

**Alternative: Use Coolify Backup Feature**
- If Coolify has automatic backups, verify the latest backup exists
- Create manual backup before upgrade

### 3. Document Current Production State

```bash
# Find production Rails container by image tag (exclude staging v4.9.1-fazer-ai.2-ee)
PROD_RAILS=$(docker ps --format '{{.Names}}\t{{.Image}}' | grep rails | grep -v "v4.9.1-fazer-ai.2-ee" | head -1 | cut -f1)

if [ -z "$PROD_RAILS" ]; then
  echo "ERROR: Production Rails container not found."
  echo "List all containers: docker ps --format 'table {{.Names}}\t{{.Image}}' | grep rails"
  exit 1
fi

echo "Using production container: $PROD_RAILS"

CURRENT_VERSION=$(docker exec "$PROD_RAILS" bundle exec rails runner "puts Chatwoot.config[:version]")
CURRENT_IMAGE=$(docker inspect "$PROD_RAILS" --format '{{.Config.Image}}')

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
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:main-ee'  # Current (or tag current state)
  pull_policy: if_not_present
sidekiq:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:main-ee'  # Current (or tag current state)
  pull_policy: if_not_present
```

**Or if you want to tag current state:**

```bash
# Tag current working production state (optional but recommended)
git tag production-backup-$(date +%Y%m%d) <current-commit>
git push origin production-backup-$(date +%Y%m%d)
```

## Production Upgrade Steps

### Step 1: Schedule Maintenance Window

- [ ] Choose low-traffic period (typically off-hours)
- [ ] Notify team/users (if applicable)
- [ ] Allocate 30-60 minutes for upgrade
- [ ] Have rollback plan ready
- [ ] Have backup verified

### Step 2: Configure Environment Variables (Security)

**⚠️ CRITICAL: Before updating compose file, ensure all sensitive credentials are configured as Environment Variables in Coolify.**

In Coolify → Production Service → Environment Variables, configure:

**Required Environment Variables:**
- `FRONTEND_URL` - Your production frontend URL
- `SERVICE_USER_POSTGRES` - PostgreSQL username
- `SERVICE_PASSWORD_POSTGRES` - PostgreSQL password
- `SERVICE_PASSWORD_64_SECRETKEYBASE` - Rails secret key base
- `SERVICE_PASSWORD_REDIS` - Redis password
- `SERVICE_PASSWORD_64_BAILEYSDEFAULTAPIKEY` - Baileys API key
- `SMTP_ADDRESS` - SMTP server address (e.g., smtp.gmail.com)
- `SMTP_PORT` - SMTP port (e.g., 587)
- `SMTP_USERNAME` - SMTP username/email
- `SMTP_PASSWORD` - SMTP password ⚠️ **SENSITIVE**
- `MAIL_SENDER` - Email sender address
- `BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME` - Baileys client name
- `BAILEYS_PROVIDER_DEFAULT_URL` - Baileys API URL (optional, defaults to http://baileys-api:3025)
- `BAILEYS_CLIENT_VERSION` - Baileys client version (optional)
- `DEFAULT_LOCALE` - Default locale (optional, defaults to 'en')

**Security Best Practices:**
- ✅ Use Coolify's secure environment variable storage
- ✅ Never commit credentials to git
- ✅ Use strong, unique passwords
- ✅ Rotate credentials periodically
- ✅ Limit access to environment variables

### Step 3: Update Production Docker Compose

In Coolify → Production Service:

**⚠️ IMPORTANT: All sensitive credentials must be configured as Environment Variables in Coolify, NOT in the compose file.**

```yaml
version: '3'
services:
  rails:
    image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee'
    pull_policy: if_not_present  # ✅ Changed from 'always'
    volumes:
      - 'storage:/app/storage'
      - 'assets:/app/public/assets'
      # ✅ Note: Production uses customizations built into the image (no volume mounts needed)
      # ❌ REMOVED: Azure OpenAI patch (no longer in codebase - removed in v4.9.1-fazer-ai.2)
      # ❌ REMOVED: WhatsApp patch (using standard Chatwoot implementation)
    depends_on:
      - postgres
      - redis
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
      - DEFAULT_LOCALE=${DEFAULT_LOCALE:-en}  # ✅ From env var
      - 'FRONTEND_URL=${FRONTEND_URL}'
      - 'INTERNAL_HOST_URL=http://rails:3000'
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=5432
      - 'POSTGRES_USERNAME=${SERVICE_USER_POSTGRES}'
      - 'POSTGRES_PASSWORD=${SERVICE_PASSWORD_POSTGRES}'
      - 'POSTGRES_DATABASE=${POSTGRES_DB:-chatwoot_production}'
      - 'SECRET_KEY_BASE=${SERVICE_PASSWORD_64_SECRETKEYBASE}'
      - 'REDIS_URL=redis://redis:6379'
      - 'REDIS_PASSWORD=${SERVICE_PASSWORD_REDIS}'
      - 'BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME=${BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME}'
      - 'BAILEYS_PROVIDER_DEFAULT_URL=${BAILEYS_PROVIDER_DEFAULT_URL:-http://baileys-api:3025}'
      - 'BAILEYS_PROVIDER_DEFAULT_API_KEY=${SERVICE_PASSWORD_64_BAILEYSDEFAULTAPIKEY}'
      - BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL=true
      # ✅ All SMTP credentials from environment variables
      - 'SMTP_ADDRESS=${SMTP_ADDRESS}'
      - 'SMTP_PORT=${SMTP_PORT:-587}'
      - 'SMTP_USERNAME=${SMTP_USERNAME}'
      - 'SMTP_PASSWORD=${SMTP_PASSWORD}'
      - 'SMTP_AUTHENTICATION=${SMTP_AUTHENTICATION:-login}'
      - 'SMTP_ENABLE_STARTTLS_AUTO=${SMTP_ENABLE_STARTTLS_AUTO:-true}'
      - 'MAIL_SENDER=${MAIL_SENDER}'
      - 'BAILEYS_CLIENT_VERSION=${BAILEYS_CLIENT_VERSION:-2.3000.1027934701}'
    entrypoint: docker/entrypoints/rails.sh
    command:
      - bundle
      - exec
      - rails
      - s
      - '-p'
      - '3000'
      - '-b'
      - 0.0.0.0
    restart: always
    ports:
      - '3000:3000'
    post_start:
      - command:
        - bundle
        - exec
        - rails
        - 'db:chatwoot_prepare'
    healthcheck:
      test:
        - CMD-SHELL
        - 'wget -qO- --header="Accept: text/html" http://127.0.0.1:3000/'
      interval: 60s
      timeout: 20s
      retries: 10

  sidekiq:
    image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee'
    pull_policy: if_not_present  # ✅ Changed from 'always'
    volumes:
      - 'storage:/app/storage'
      # ✅ Note: Production uses customizations built into the image (no volume mounts needed)
      # ❌ REMOVED: Azure OpenAI patch (no longer in codebase - removed in v4.9.1-fazer-ai.2)
    depends_on:
      - postgres
      - redis
    environment:
      # Same environment variables as rails (excluding FRONTEND_URL, ports)
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
      - DEFAULT_LOCALE=${DEFAULT_LOCALE:-en}  # ✅ From env var
      - 'INTERNAL_HOST_URL=http://rails:3000'
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=5432
      - 'POSTGRES_USERNAME=${SERVICE_USER_POSTGRES}'
      - 'POSTGRES_PASSWORD=${SERVICE_PASSWORD_POSTGRES}'
      - 'POSTGRES_DATABASE=${POSTGRES_DB:-chatwoot_production}'
      - 'SECRET_KEY_BASE=${SERVICE_PASSWORD_64_SECRETKEYBASE}'
      - 'REDIS_URL=redis://redis:6379'
      - 'REDIS_PASSWORD=${SERVICE_PASSWORD_REDIS}'
      - 'BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME=${BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME}'
      - 'BAILEYS_PROVIDER_DEFAULT_URL=${BAILEYS_PROVIDER_DEFAULT_URL:-http://baileys-api:3025}'
      - 'BAILEYS_PROVIDER_DEFAULT_API_KEY=${SERVICE_PASSWORD_64_BAILEYSDEFAULTAPIKEY}'
      - BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL=true
      # ✅ All SMTP credentials from environment variables
      - 'SMTP_ADDRESS=${SMTP_ADDRESS}'
      - 'SMTP_PORT=${SMTP_PORT:-587}'
      - 'SMTP_USERNAME=${SMTP_USERNAME}'
      - 'SMTP_PASSWORD=${SMTP_PASSWORD}'
      - 'SMTP_AUTHENTICATION=${SMTP_AUTHENTICATION:-login}'
      - 'SMTP_ENABLE_STARTTLS_AUTO=${SMTP_ENABLE_STARTTLS_AUTO:-true}'
      - 'MAIL_SENDER=${MAIL_SENDER}'
    command:
      - bundle
      - exec
      - sidekiq
      - '-C'
      - config/sidekiq.yml
    restart: always
    healthcheck:
      test:
        - CMD-SHELL
        - 'ps aux | grep [s]idekiq'
      interval: 20s
      timeout: 20s
      retries: 10

  # ... postgres, redis, baileys-api services remain unchanged
```

**Key Changes:**
1. ✅ Image: `ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee` (Azure OpenAI removed)
2. ✅ Pull policy: `if_not_present` (prevents auto-updates)
3. ✅ Customizations built into image (production doesn't need volume mounts)
4. ❌ Removed: Azure OpenAI customization (confirmed removed from codebase)
5. ❌ Removed: WhatsApp webhook fixes (using standard Chatwoot implementation)
6. ✅ **Security**: All sensitive credentials moved to environment variables (SMTP, passwords, etc.)

**Double-check:**
- [ ] Using **Production** service (not staging!)
- [ ] Image tag is correct: `v4.9.1-fazer-ai.2-ee` (Azure OpenAI removed version)
- [ ] `pull_policy: if_not_present` (prevents unexpected pulls)
- [ ] No volume mounts for customizations (production has them built into image)
- [ ] **NO hardcoded credentials in compose file** (all use `${ENV_VAR}`)
- [ ] All environment variables configured in Coolify Environment Variables section
- [ ] Staging successfully running same image version (validated ✅)

### Step 4: Deploy in Coolify

1. **Save the compose file**
2. **Click "Deploy"**
3. **Monitor deployment closely:**
   - Watch for errors in Coolify logs
   - Check service health indicators
   - Monitor container startup
   - Check for migration errors

### Step 5: Verify Deployment

**Immediate checks (within 5 minutes):**

```bash
# Find production Rails container by image tag
# Production should be running main-ee or v4.8.0-fazer-ai.5-ee (current) or v4.9.1-fazer-ai.2-ee (after upgrade)
# Exclude staging by excluding v4.9.1-fazer-ai.2-ee if we're checking before upgrade
PROD_RAILS=$(docker ps --format '{{.Names}}\t{{.Image}}' | grep rails | grep -v "v4.9.1-fazer-ai.2-ee" | head -1 | cut -f1)

# Alternative: If you know the production image tag, use it explicitly:
# PROD_RAILS=$(docker ps --format '{{.Names}}\t{{.Image}}' | grep "main-ee\|v4.8.0-fazer-ai.5-ee" | grep rails | cut -f1 | head -1)

# If not found, list all containers to identify manually:
# docker ps --format "table {{.Names}}\t{{.Image}}" | grep rails

# Verify container was found
if [ -z "$PROD_RAILS" ]; then
  echo "ERROR: Production Rails container not found."
  echo "List all containers: docker ps --format 'table {{.Names}}\t{{.Image}}' | grep rails"
  exit 1
fi

echo "Using production container: $PROD_RAILS"

# Check services are running
docker ps | grep rails
docker ps | grep sidekiq

# Check version
docker exec "$PROD_RAILS" bundle exec rails runner "puts Chatwoot.config[:version]"
# Should show: 4.9.1-fazer-ai.2

# Check image
docker inspect "$PROD_RAILS" --format '{{.Config.Image}}'
# Should show: ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee

# Check for errors
docker logs "$PROD_RAILS" --tail 50 | grep -i error
```

**⚠️ CRITICAL: Verify Enterprise Module Loading (Prevent Zeitwerk Errors)**

Zeitwerk autoloading errors can occur if Enterprise modules aren't loaded properly. Verify before proceeding:

```bash
# Find production Rails container by image tag (exclude staging)
PROD_RAILS=$(docker ps --format '{{.Names}}\t{{.Image}}' | grep rails | grep -v "v4.9.1-fazer-ai.2-ee" | head -1 | cut -f1)

if [ -z "$PROD_RAILS" ]; then
  echo "ERROR: Production Rails container not found."
  echo "List all containers: docker ps --format 'table {{.Names}}\t{{.Image}}' | grep rails"
  exit 1
fi

echo "Using production container: $PROD_RAILS"

# 1. Verify Enterprise folder exists in image
docker exec "$PROD_RAILS" ls -la /app/enterprise 2>&1 | head -5
# Should show directory listing, not "No such file or directory"

# 2. Verify Enterprise detection
docker exec "$PROD_RAILS" bundle exec rails runner "puts ChatwootApp.enterprise?"
# Should output: true

# 3. Verify extensions are loaded
docker exec "$PROD_RAILS" bundle exec rails runner "puts ChatwootApp.extensions.inspect"
# Should output: ["enterprise"] (not [])

# 4. Check for Zeitwerk autoloading errors in logs
docker logs "$PROD_RAILS" --tail 200 | grep -i "zeitwerk\|autoload\|NameError\|expected.*to.*be.*defined"
# Should return NO results (empty output)

# 5. Verify Enterprise modules can be loaded (test constant lookup)
docker exec "$PROD_RAILS" bundle exec rails runner "
  begin
    puts 'Enterprise namespace exists: ' + (defined?(Enterprise) ? 'YES' : 'NO')
    if defined?(Enterprise)
      puts 'Sample Enterprise module: ' + (Enterprise.const_defined?(:Account) ? 'Account module found' : 'Account module NOT found')
    end
  rescue => e
    puts 'ERROR: ' + e.message
    exit 1
  end
"
# Should show: Enterprise namespace exists: YES, Sample Enterprise module: Account module found

# 6. Check Rails console can start without errors
docker exec "$PROD_RAILS" bundle exec rails runner "puts 'Rails loaded successfully'"
# Should output: Rails loaded successfully (no errors)
```

**If any of these checks fail:**
- **STOP** - Do not proceed with upgrade
- Check logs for detailed error messages
- Verify the image has Enterprise code (`v4.9.1-fazer-ai.2-ee` should have it)
- Compare with staging (which is working) - check what's different
- Consider rollback if critical

**Migration check:**

```bash
# Check migration status (PROD_RAILS should already be set from previous step)
docker exec "$PROD_RAILS" bundle exec rails db:migrate:status | tail -20

# Should show no pending migrations (all "up")
# If pending, run:
docker exec "$PROD_RAILS" bundle exec rails db:migrate
```

**Health check:**

```bash
# Check health endpoint
curl -I https://your-production-url.com/

# Should return: 200 OK
```

### Step 6: Functional Testing

**Before functional testing, verify no Zeitwerk errors:**

```bash
# PROD_RAILS should already be set from Step 5, but verify:
if [ -z "$PROD_RAILS" ]; then
  PROD_RAILS=$(docker ps --format '{{.Names}}\t{{.Image}}' | grep rails | grep -v "v4.9.1-fazer-ai.2-ee" | head -1 | cut -f1)
  if [ -z "$PROD_RAILS" ]; then
    echo "ERROR: Production Rails container not found."
    echo "List all containers: docker ps --format 'table {{.Names}}\t{{.Image}}' | grep rails"
    exit 1
  fi
fi

# Final check for Zeitwerk/autoloading errors
docker logs "$PROD_RAILS" --tail 500 | grep -iE "zeitwerk|NameError|uninitialized constant|expected.*to.*be.*defined" | head -20
# Should return NO errors

# Test Rails console loads without errors
docker exec "$PROD_RAILS" bundle exec rails runner "
  puts 'Enterprise loaded: ' + ChatwootApp.enterprise?.to_s
  puts 'Extensions: ' + ChatwootApp.extensions.inspect
  puts 'Rails boot successful'
"
# Should show: Enterprise loaded: true, Extensions: ["enterprise"], Rails boot successful
```

Test critical features:

- [ ] **No Zeitwerk errors** - Verified above (logs clean, Rails loads)
- [ ] **Enterprise modules loaded** - ChatwootApp.extensions returns ["enterprise"]
- [ ] **Login works** - Can log in to dashboard
- [ ] **Conversations load** - Can view conversations list
- [ ] **Messages send** - Can send/receive messages
- [ ] **Settings accessible** - Can access settings page
- [ ] **Enterprise features** - All Enterprise features work
- [ ] **Custom automation filters** - Create/edit automation rules with custom attribute filters
- [ ] **Custom attributes display** - Settings → Custom Attributes shows attributes correctly (v4.9.1 fix)
- [ ] **WhatsApp channels** - WhatsApp channels work with standard Chatwoot implementation
- [ ] **No errors in UI** - Check browser console for errors

### Step 7: Monitor (24-48 hours)

**First hour:**
- [ ] Check logs every 15 minutes
- [ ] Monitor error rates
- [ ] Test critical features
- [ ] Check performance metrics
- [ ] Verify no increase in error rates

**First 24 hours:**
- [ ] Check logs every few hours
- [ ] Monitor for unusual errors
- [ ] Verify all features still work
- [ ] Check database performance
- [ ] Monitor resource usage (CPU, memory)

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
       image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai.5-ee'  # Previous production
       pull_policy: if_not_present
     sidekiq:
       image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai.5-ee'  # Previous production
       pull_policy: if_not_present
     ```
   - **Note**: Previous production version had customizations built into the image (no volume mounts needed)
   - Save and redeploy

2. **Verify rollback:**
   ```bash
   PROD_RAILS=$(docker ps --format '{{.Names}}\t{{.Image}}' | grep rails | grep -v "v4.9.1-fazer-ai.2-ee" | head -1 | cut -f1)
   if [ -z "$PROD_RAILS" ]; then
     echo "ERROR: Production Rails container not found."
     exit 1
   fi
   docker exec "$PROD_RAILS" bundle exec rails runner "puts Chatwoot.config[:version]"
   # Should show previous version
   ```

### Full Rollback (If migrations ran)

If database migrations completed but you need to rollback:

1. **Stop services** (in Coolify)

2. **Restore database** (if backup available):
   ```bash
   # Find production PostgreSQL container
   POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}\t{{.Image}}' | grep postgres | grep -v "v4.9.1-fazer-ai.2-ee" | head -1 | cut -f1)
   DB_USER=$(docker exec "$POSTGRES_CONTAINER" printenv POSTGRES_USER)
   BACKUP_FILE="/tmp/chatwoot_prod_<timestamp>.sql"  # Use your actual backup file
   
   # Verify backup file exists
   if [ ! -f "$BACKUP_FILE" ]; then
     echo "ERROR: Backup file not found: $BACKUP_FILE"
     exit 1
   fi
   
   echo "Restoring from backup: $BACKUP_FILE"
   # Restore from backup
   docker exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" chatwoot_production < "$BACKUP_FILE"
   
   # Alternative: If you know exact container and user:
   # docker exec -i postgres-f8kkkgcsko4sogs88k8c80ok \
   #   psql -U 6IjRtavqqNlMy0Ad chatwoot_production < /tmp/chatwoot_prod_2025-12-25_1928.sql
   ```

3. **Revert image** (as above)

4. **Restart services**

## Security Checklist

Before deploying, verify:

- [ ] **No hardcoded credentials** in docker-compose file
- [ ] All passwords use `${ENV_VAR}` syntax
- [ ] All sensitive data configured in Coolify Environment Variables
- [ ] SMTP credentials not visible in compose file
- [ ] Database passwords not visible in compose file
- [ ] API keys not visible in compose file
- [ ] Environment variables are properly secured in Coolify

**Example of what NOT to do:**
```yaml
# ❌ DON'T DO THIS
environment:
  - SMTP_PASSWORD=obswlqfuqanyoked  # ❌ Hardcoded password
  - POSTGRES_PASSWORD=mypassword    # ❌ Hardcoded password
```

**Example of what TO do:**
```yaml
# ✅ DO THIS
environment:
  - 'SMTP_PASSWORD=${SMTP_PASSWORD}'        # ✅ From environment variable
  - 'POSTGRES_PASSWORD=${SERVICE_PASSWORD_POSTGRES}'  # ✅ From environment variable
```

## Post-Upgrade Tasks

### 0. Version String Consistency (Best Practice)

**Important:** The version in `config/app.yml` should always match the Docker image tag version.

**Current situation:**
- Docker image tag: `v4.9.1-fazer-ai.2-ee`
- `config/app.yml` version: `4.9.1-fazer-ai.1` (minor mismatch - acceptable for this build)

**For future builds:**
- When creating a new version tag (e.g., `v4.9.1-fazer-ai.3-ee`), always update `config/app.yml` first:
  ```yaml
  shared: &shared
    version: '4.9.1-fazer-ai.3'  # Match the tag version
  ```
- Then commit and tag:
  ```bash
  git add config/app.yml
  git commit -m "chore: bump version to 4.9.1-fazer-ai.3"
  git tag -a v4.9.1-fazer-ai.3-ee -m "v4.9.1-fazer-ai.3: description"
  git push origin v4.9.1-fazer-ai.3-ee
  ```

**Why this matters:**
- The version string displayed in the UI should match the Docker image tag for clarity
- Makes debugging easier (can quickly see which version is running)
- Prevents confusion between image tags and application version strings

### 1. Verify Customizations in Image

Production uses customizations built into the image (no volume mounts). Verify they're present:

```bash
# Find production Rails container by image tag (exclude staging)
PROD_RAILS=$(docker ps --format '{{.Names}}\t{{.Image}}' | grep rails | grep -v "v4.9.1-fazer-ai.2-ee" | head -1 | cut -f1)

if [ -z "$PROD_RAILS" ]; then
  echo "ERROR: Production Rails container not found."
  echo "List all containers: docker ps --format 'table {{.Names}}\t{{.Image}}' | grep rails"
  exit 1
fi

echo "Using production container: $PROD_RAILS"

# Verify custom files exist in image
docker exec "$PROD_RAILS" ls -la app/javascript/dashboard/helper/automationHelper.js
docker exec "$PROD_RAILS" ls -la app/services/filter_service.rb

# Should show files exist (not volume mounts in production)
```

**Note**: Production image has customizations baked in, unlike staging which uses volume mounts for easier iteration.

### 2. Update Documentation

- [ ] Update `deployment/PRODUCTION_CHANGELOG.md`
- [ ] Document any issues encountered
- [ ] Note configuration changes
- [ ] Update version references

### 3. Monitor and Validate

- [ ] Monitor for 1 week minimum
- [ ] Track error rates
- [ ] Verify performance metrics
- [ ] Collect user feedback

### 4. Communication

- [ ] Notify team of successful upgrade
- [ ] Document any new features/improvements
- [ ] Share lessons learned

## Success Criteria

Upgrade is successful when:

- [ ] Services running stable for 48+ hours
- [ ] No critical errors in logs
- [ ] All features working correctly:
  - [ ] Custom automation filters
  - [ ] Enterprise features
  - [ ] Custom attributes display correctly (v4.9.1 fix)
  - [ ] WhatsApp channels working
- [ ] Performance acceptable (no degradation)
- [ ] No user complaints
- [ ] Database migrations completed
- [ ] Version displayed correctly (4.9.1-fazer-ai.2)

## Common Issues & Solutions

### Issue: Services won't start

**Solution:**
- Check logs: `docker logs <container>`
- Verify image exists: `docker manifest inspect ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee`
- Check environment variables are properly configured in Coolify
- Verify staging is running same version successfully (reference point)
- Rollback if needed

### Issue: Migration fails

**Solution:**
- Check migration logs
- Verify database permissions
- Check disk space
- Restore from backup and rollback

### Issue: Custom features not working

**Solution:**
- Verify custom files are in image:
  ```bash
  # PROD_RAILS should be set, but if not:
  PROD_RAILS=$(docker ps --format '{{.Names}}\t{{.Image}}' | grep rails | grep -v "v4.9.1-fazer-ai.2-ee" | head -1 | cut -f1)
  
  if [ -z "$PROD_RAILS" ]; then
    echo "ERROR: Production Rails container not found."
    exit 1
  fi
  
  docker exec "$PROD_RAILS" ls -la app/javascript/dashboard/helper/automationHelper.js
  docker exec "$PROD_RAILS" ls -la app/services/filter_service.rb
  ```
- Check logs for errors
- Verify Enterprise features enabled
- Rollback if critical

### Issue: Zeitwerk Autoloading Errors

**Symptoms:**
- Errors like: `Zeitwerk::NameError: expected file ... to define constant ...`
- `NameError: uninitialized constant Enterprise::...`
- Rails fails to start with constant lookup errors
- Module not found errors during boot

**Root Causes:**
1. **Enterprise folder missing in image** - Check if `/app/enterprise` exists
2. **ChatwootApp.enterprise? returns false** - Enterprise detection failing
3. **ChatwootApp.extensions returns []** - No extensions loaded
4. **Module loading order issues** - Enterprise modules loaded before base classes
5. **File/constant naming mismatch** - Zeitwerk can't map files to constants

**Solution Steps:**

1. **Verify Enterprise folder exists:**
   ```bash
   PROD_RAILS=$(docker ps --format '{{.Names}}\t{{.Image}}' | grep rails | grep -v "v4.9.1-fazer-ai.2-ee" | head -1 | cut -f1)
   if [ -z "$PROD_RAILS" ]; then
     echo "ERROR: Production Rails container not found."
     exit 1
   fi
   docker exec "$PROD_RAILS" ls -la /app/enterprise
   # Should show directory listing
   ```

2. **Verify Enterprise detection:**
   ```bash
   docker exec "$PROD_RAILS" bundle exec rails runner "puts ChatwootApp.enterprise?"
   # Should output: true
   ```

3. **Check extensions:**
   ```bash
   docker exec "$PROD_RAILS" bundle exec rails runner "puts ChatwootApp.extensions.inspect"
   # Should output: ["enterprise"]
   ```

4. **Check for DISABLE_ENTERPRISE env var:**
   ```bash
   docker exec "$PROD_RAILS" env | grep DISABLE_ENTERPRISE
   # Should be empty or not set to 'true'/'1'
   ```

5. **Verify image is EE version:**
   ```bash
   docker inspect "$PROD_RAILS" --format '{{.Config.Image}}'
   # Should end with: -ee (e.g., v4.9.1-fazer-ai.2-ee)
   ```

6. **Check logs for specific Zeitwerk errors:**
   ```bash
   docker logs "$PROD_RAILS" --tail 500 | grep -i "zeitwerk\|NameError\|expected.*to.*be.*defined"
   # Look for specific file/constant that's failing
   ```

**If Enterprise folder missing:**
- The image might not be the EE version
- Verify you're using `v4.9.1-fazer-ai.2-ee` (with `-ee` suffix)
- Check GitHub Container Registry that the image exists and is EE version

**If Enterprise detection fails:**
- Check environment variables (DISABLE_ENTERPRISE should not be set)
- Verify database config (should be set to 'enterprise')
- Check that the enterprise folder actually exists in the image

**Prevention (Already in place):**
- ✅ Using EE image tag: `v4.9.1-fazer-ai.2-ee`
- ✅ Staging successfully running same version (validates Enterprise modules load)
- ✅ Verification steps above will catch issues before they become critical

**Rollback if needed:**
- If Zeitwerk errors prevent Rails from starting, rollback immediately
- Previous production version (`v4.8.0-fazer-ai.5-ee`) was working

### Issue: Performance degradation

**Solution:**
- Check resource usage: `docker stats`
- Review slow queries
- Check for memory leaks
- Consider rollback if severe

## Key Improvements in v4.9.1-fazer-ai.2

1. **Official Chatwoot v4.9.1**:
   - ✅ Fixed custom attributes display issue
   - ✅ Editor improvements
   - ✅ Package updates

2. **Your Customizations Preserved (Built into Image)**:
   - ✅ Custom automation filters
   - ✅ Enterprise unlock modifications
   - ✅ Custom filter service
   - ✅ Pricing plan fix

3. **Cleanup**:
   - ❌ Removed Azure OpenAI customization (confirmed removed from codebase)
   - ❌ Removed WhatsApp webhook fixes (using standard Chatwoot implementation)

4. **Verification**:
   - ✅ Staging successfully running with v4.9.1-fazer-ai.2-ee
   - ✅ Azure OpenAI code confirmed removed
   - ✅ All customizations working correctly

## Timeline Example

**Week 1:** Staging deployment ✅ **COMPLETED**
- ✅ Deployed v4.9.1-fazer-ai.2-ee to staging
- ✅ Verified Azure OpenAI customization removed
- ✅ Tested thoroughly
- ✅ Monitoring for issues
- ✅ All features working correctly

**Week 2:** Production upgrade preparation
- [ ] Create backup
- [ ] Schedule maintenance window
- [ ] Prepare rollback plan
- [ ] Verify environment variables configured
- [ ] Review staging status (currently running successfully)

**Week 2-3:** Production upgrade
- [ ] Deploy during maintenance window
- [ ] Verify immediately
- [ ] Monitor closely for 48 hours

**Week 3+:** Post-upgrade monitoring
- [ ] Monitor for 1 week
- [ ] Test all features
- [ ] Document any issues
- [ ] Mark upgrade as successful

## Quick Reference

**Current Production:**
```yaml
image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai.5-ee'  # Current
pull_policy: if_not_present
```

**Target Production:**
```yaml
image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee'  # Versioned (Azure OpenAI removed)
pull_policy: if_not_present  # Safe
```

**Staging (Reference):**
```yaml
image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.9.1-fazer-ai.2-ee'  # Successfully running ✅
pull_policy: if_not_present
```

**Rollback:**
```yaml
image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai.5-ee'  # Previous production
pull_policy: if_not_present
```

---

## Staging Validation Status

✅ **Staging Successfully Deployed**
- **Image**: `v4.9.1-fazer-ai.2-ee`
- **Status**: Running successfully
- **Azure OpenAI**: Confirmed removed from codebase
- **Customizations**: All working correctly
- **Environment Variables**: Properly configured
- **Zeitwerk/Autoloading**: No errors (Enterprise modules load correctly)
- **Enterprise Detection**: ChatwootApp.enterprise? returns true
- **Extensions**: ChatwootApp.extensions returns ["enterprise"]

**Status**: ✅ **Ready for production upgrade** - Staging validated successfully

**Zeitwerk Safety:** Since staging is running the same image (`v4.9.1-fazer-ai.2-ee`) without Zeitwerk errors, production should be safe. However, always verify Enterprise module loading immediately after deployment using the verification steps in Step 5.


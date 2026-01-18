# Production Image Reference: v4.8.0-fazer-ai.5

## Current Production Status

**Version**: v4.8.0-fazer-ai.5 (Build 7a2764b)  
**Current Image**: `ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee`

## Image Options

### Option 1: Keep Using fazer-ai Image (Recommended for Stability)

If you want to **continue using v4.8.0-fazer-ai.5** without any changes, use:

```yaml
rails:
  image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'
  pull_policy: if_not_present  # ✅ Prevents unexpected updates

sidekiq:
  image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'
  pull_policy: if_not_present  # ✅ Prevents unexpected updates
```

**Pros:**
- ✅ Stable, tested version
- ✅ Won't change unless you explicitly update
- ✅ Currently working in production

**Cons:**
- Uses fazer-ai repository (not your fork)
- No customizations from your fork included

### Option 2: Use Versioned Tag from Your Fork (If Available)

If you've built v4.8.0-fazer-ai.5 from your fork, you might have:

```yaml
rails:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai.5-ee'
  pull_policy: if_not_present

sidekiq:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai.5-ee'
  pull_policy: if_not_present
```

**Check if this tag exists:**
```bash
docker manifest inspect ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai.5-ee
```

### Option 3: Use main-ee Tag (NOT Recommended for Production)

**⚠️ DO NOT USE `main-ee` IN PRODUCTION**

```yaml
# ❌ DON'T DO THIS IN PRODUCTION
rails:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:main-ee'  # ❌ Moving target
```

**Why not:**
- `main-ee` rebuilds on every push to main branch
- Version changes without your control
- Can break production unexpectedly
- No version pinning

## Recommended Production Configuration

For **stable production** with v4.8.0-fazer-ai.5:

```yaml
services:
  rails:
    image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'
    pull_policy: if_not_present  # ✅ Critical: prevents auto-updates

  sidekiq:
    image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'
    pull_policy: if_not_present  # ✅ Critical: prevents auto-updates
```

## Important: pull_policy Settings

### ✅ Use `if_not_present` in Production

```yaml
pull_policy: if_not_present
```

**Benefits:**
- Only pulls if image doesn't exist locally
- Prevents unexpected updates
- Maintains version stability

### ❌ Avoid `always` in Production

```yaml
pull_policy: always  # ❌ Dangerous in production
```

**Risks:**
- Pulls latest image every time container restarts
- Can break production unexpectedly
- No version control

## Migration from main-ee to Versioned Tag

If you're currently using `main-ee` and want to pin to v4.8.0-fazer-ai.5:

### Step 1: Update docker-compose

Change from:
```yaml
rails:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:main-ee'
  pull_policy: always
```

To:
```yaml
rails:
  image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'
  pull_policy: if_not_present
```

### Step 2: Pull and Verify Image

```bash
# Pull the versioned image
docker pull ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee

# Verify it's the correct version
docker run --rm ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee \
  bundle exec rails runner "puts Chatwoot.config[:version]"
# Should show: 4.8.0-fazer-ai.5
```

### Step 3: Redeploy

In Coolify (or your deployment tool):
1. Update docker-compose configuration
2. Save changes
3. Redeploy services

## Verification

After updating, verify the version:

```bash
# Get container name
RAILS_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i rails | head -1)

# Check version
docker exec $RAILS_CONTAINER bundle exec rails runner "puts Chatwoot.config[:version]"
# Expected: 4.8.0-fazer-ai.5

# Check image
docker inspect $RAILS_CONTAINER --format '{{.Config.Image}}'
# Expected: ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee
```

## Summary

**To keep v4.8.0-fazer-ai.5 in production:**

✅ **Use**: `ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee`  
✅ **Pull Policy**: `if_not_present`  
❌ **Don't Use**: `main-ee` tag in production

**Current docker-compose.coolify.yaml already uses the correct configuration** ✅




# Production: Pin to v4.8.0-fazer-ai.5

## Current Situation

Your production is using:
- **Image**: `ghcr.io/lucouto/chatwoot.fazer.ai:main-ee` ⚠️ (moving target)
- **pull_policy**: `always` ⚠️ (dangerous)
- **Volume mount**: Azure OpenAI patch (fine)

## Problem

1. **`main-ee` is unstable** - Changes on every push to main
2. **`pull_policy: always`** - Pulls latest every restart (can break production)
3. **No version pinning** - Can't reproduce exact state

## Solution: Pin to Stable Version

### Step 1: Check Current Version

First, verify what version your current `main-ee` actually is:

```bash
# Get container name
RAILS_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i rails | head -1)

# Check version
docker exec $RAILS_CONTAINER bundle exec rails runner "puts Chatwoot.config[:version]"
```

### Step 2: Options to Pin Version

#### Option A: Use fazer-ai Image (If It Has Your Customizations)

If `ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee` includes your customizations:

```yaml
rails:
  image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'  # ✅ Versioned
  pull_policy: if_not_present  # ✅ Changed from always
  volumes:
    - 'storage:/app/storage'
    - 'assets:/app/public/assets'
    - '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'

sidekiq:
  image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'  # ✅ Versioned
  pull_policy: if_not_present  # ✅ Changed from always
  volumes:
    - 'storage:/app/storage'
    - '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'
```

**Check if fazer-ai image has your customizations:**
```bash
# Test if it has custom automation filters
docker run --rm ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee \
  grep -q "getCustomAttributeInputType" app/javascript/dashboard/helper/automationHelper.js && echo "Has customizations" || echo "Missing customizations"
```

#### Option B: Build and Tag Your Fork (Recommended if fazer-ai doesn't have customizations)

Since you're using your fork (`ghcr.io/lucouto/chatwoot.fazer.ai`), you likely need to:

1. **Find the commit that corresponds to v4.8.0-fazer-ai.5**

```bash
# Check git history for v4.8.0-fazer-ai.5
git log --oneline --all | grep -i "v4.8.0-fazer-ai.5"

# Or check what commit main-ee is at
git log --oneline origin/main | head -10
```

2. **Tag that commit** (if not already tagged):

```bash
# Find the commit hash for v4.8.0-fazer-ai.5
COMMIT_HASH=$(git log --oneline --all --grep="v4.8.0-fazer-ai.5" | head -1 | cut -d' ' -f1)

# Tag it (if needed)
git tag v4.8.0-fazer-ai.5-ee $COMMIT_HASH
git push origin v4.8.0-fazer-ai.5-ee
```

3. **Use the versioned tag**:

```yaml
rails:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai.5-ee'
  pull_policy: if_not_present  # ✅ Changed from always
  volumes:
    - 'storage:/app/storage'
    - 'assets:/app/public/assets'
    - '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'
```

#### Option C: Keep main-ee but Change pull_policy (Temporary)

If you can't immediately tag a version, at least fix the pull_policy:

```yaml
rails:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:main-ee'  # ⚠️ Still moving target
  pull_policy: if_not_present  # ✅ At least won't auto-update on restart
```

**This is better than `always`, but still not ideal.**

## Recommended Production Configuration

```yaml
version: '3'
services:
  rails:
    # Option 1: fazer-ai image (if it has your customizations)
    image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'
    # Option 2: Your fork (if fazer-ai doesn't have customizations)
    # image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai.5-ee'
    
    pull_policy: if_not_present  # ✅ CRITICAL: Changed from always
    
    volumes:
      - 'storage:/app/storage'
      - 'assets:/app/public/assets'
      - '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'
    
    # ... rest of config stays the same

  sidekiq:
    # Same image as rails
    image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'
    # OR: image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai.5-ee'
    
    pull_policy: if_not_present  # ✅ CRITICAL: Changed from always
    
    volumes:
      - 'storage:/app/storage'
      - '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'
    
    # ... rest of config stays the same
```

## Critical Changes

1. ✅ **Change `pull_policy: always` → `pull_policy: if_not_present`**
   - Prevents unexpected updates on container restart
   - Only pulls if image doesn't exist locally

2. ✅ **Change `main-ee` → versioned tag** (when possible)
   - `v4.8.0-fazer-ai.5-ee` (either fazer-ai or your fork)
   - Provides version stability

## Next Steps

1. **Immediate**: Change `pull_policy` to `if_not_present` (prevents auto-updates)
2. **Short-term**: Verify if fazer-ai image has your customizations
3. **If fazer-ai has customizations**: Switch to `ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee`
4. **If fazer-ai doesn't have customizations**: Tag your fork and use `ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai.5-ee`

## Your Customizations

Based on your current setup, you have:

### Built into Image (main-ee):
- Custom automation filters
- Enterprise unlock modifications
- Other custom code

### Volume-Mounted:
- Azure OpenAI patch (`base_open_ai_service.rb`) - ✅ Keep this

The volume mount for Azure OpenAI patch should remain regardless of which image you use.




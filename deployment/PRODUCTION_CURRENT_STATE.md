# Current Production State Analysis

## Actual Production Configuration

**Image**: `ghcr.io/lucouto/chatwoot.fazer.ai:main-ee`  
**Version**: Unknown (moving target - changes with every push to main)  
**Customizations Method**: Hybrid (image + volume mount)

## Current Setup

### Volume Mounts
1. ✅ `storage:/app/storage` - File storage
2. ✅ `assets:/app/public/assets` - Compiled assets
3. ✅ `/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb` - Azure OpenAI patch (volume-mounted)

### Issues with Current Setup

1. **⚠️ Using `main-ee` Tag**
   - `main-ee` is a **moving target**
   - Rebuilds on every push to `main` branch
   - Version changes without control
   - **NOT suitable for production**

2. **⚠️ `pull_policy: always`**
   - Pulls latest image on every container restart
   - Can break production unexpectedly
   - **Should be `if_not_present`**

3. **✅ Volume Mount for Azure OpenAI**
   - This is fine - allows patching without rebuilding

## Recommended Changes

### Option 1: Switch to fazer-ai Image (If It Has Your Customizations)

If `ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee` includes your customizations:

```yaml
rails:
  image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'
  pull_policy: if_not_present  # ✅ Changed from always
  volumes:
    - 'storage:/app/storage'
    - 'assets:/app/public/assets'
    - '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'

sidekiq:
  image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'
  pull_policy: if_not_present  # ✅ Changed from always
  volumes:
    - 'storage:/app/storage'
    - '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'
```

### Option 2: Use Versioned Tag from Your Fork

If you've built v4.8.0-fazer-ai.5 in your fork, check if this tag exists:

```bash
docker manifest inspect ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai.5-ee
```

If it exists:

```yaml
rails:
  image: 'ghcr.io/lucouto/chatwoot.fazer.ai:v4.8.0-fazer-ai.5-ee'
  pull_policy: if_not_present  # ✅ Changed from always
  volumes:
    - 'storage:/app/storage'
    - 'assets:/app/public/assets'
    - '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'
```

### Option 3: Build and Tag Your Current Working Version

If your current `main-ee` is working well, you could:

1. Check what version it actually is:
```bash
docker exec <rails-container> bundle exec rails runner "puts Chatwoot.config[:version]"
```

2. Tag that specific commit with a version tag
3. Use that version tag in production

## Immediate Action Required

### Critical: Change pull_policy

**Current (Dangerous):**
```yaml
pull_policy: always  # ❌ Pulls latest every restart
```

**Should be:**
```yaml
pull_policy: if_not_present  # ✅ Only pulls if missing locally
```

This prevents unexpected updates when containers restart.

## Your Customizations Status

Based on your compose file:

### Built into Image (from main-ee):
- ✅ Custom automation filters (automationHelper.js, filter_service.rb)
- ✅ Enterprise unlock modifications
- ✅ Other custom code changes

### Volume-Mounted:
- ✅ Azure OpenAI patch (`base_open_ai_service.rb`)

## Recommended Production Configuration

To stabilize production at v4.8.0-fazer-ai.5:

```yaml
version: '3'
services:
  rails:
    image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'  # ✅ Versioned tag
    pull_policy: if_not_present  # ✅ Changed from always
    volumes:
      - 'storage:/app/storage'
      - 'assets:/app/public/assets'
      - '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'
    # ... rest of config

  sidekiq:
    image: 'ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee'  # ✅ Versioned tag
    pull_policy: if_not_present  # ✅ Changed from always
    volumes:
      - 'storage:/app/storage'
      - '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'
    # ... rest of config
```

**Note**: This assumes fazer-ai image has your customizations. If not, you'll need to check what's actually in the fazer-ai image vs what you need.

## Verification Steps

1. **Check current version**:
```bash
docker exec <rails-container> bundle exec rails runner "puts Chatwoot.config[:version]"
```

2. **Check if fazer-ai image has your customizations**:
```bash
# Pull fazer-ai image
docker pull ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee

# Check if it has custom automation filters
docker run --rm ghcr.io/fazer-ai/chatwoot:v4.8.0-fazer-ai.5-ee \
  grep -l "getCustomAttributeInputType" app/javascript/dashboard/helper/automationHelper.js
```

3. **Compare with your current main-ee**:
```bash
# Check your main-ee version
docker exec <rails-container> bundle exec rails runner "puts Chatwoot.config[:version]"

# Check if custom files exist
docker exec <rails-container> ls -la app/javascript/dashboard/helper/automationHelper.js
```




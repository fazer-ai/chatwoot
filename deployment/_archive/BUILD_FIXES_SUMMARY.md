# Build Fixes Summary

## Overview

Documentation of all fixes applied to successfully build `v4.10.0-fazer-ai.15-ee` Docker image.

---

## Issue 1: Bundle Install Exit Code 6

### Problem
`bundle install` failing with exit code 6 - network timeout errors during gem downloads.

### Root Cause
Transient network issues when downloading gems from RubyGems.org during Docker build.

### Solution
Added retry logic with exponential backoff in Dockerfile:

```dockerfile
RUN if [ "$RAILS_ENV" = "production" ]; then \
  bundle config set without 'development test'; \
  bundle install -j 4 -r 5 --verbose || \
  (sleep 10 && bundle install -j 4 -r 5 --verbose) || \
  (sleep 20 && bundle install -j 4 -r 5 --verbose || exit 1); \
  else \
  bundle install -j 4 -r 5 --verbose || \
  (sleep 10 && bundle install -j 4 -r 5 --verbose) || \
  (sleep 20 && bundle install -j 4 -r 5 --verbose || exit 1); \
  fi
```

**What it does:**
- First attempt with `-r 5` retries and verbose output
- If fails, wait 10s and retry
- If still fails, wait 20s and final retry

**Files changed:**
- `docker/Dockerfile` (lines 69-72)

---

## Issue 2: Bundler Version Mismatch

### Problem
Build failing with dependency conflict between `devise-secure_password` and `web-console`, even though both should work with Rails 7.

### Root Cause
Dockerfile was installing **bundler 4.0.4** (latest) instead of **bundler 2.5.11** (as specified in `BUNDLER_VERSION`). Bundler 4.0.4 has stricter dependency resolution that caught a conflict that bundler 2.5.x handled more leniently.

**Why v4.9.1 worked:**
- Used bundler 2.5.x (more lenient resolver)
- Allowed the `devise-secure_password` dependency conflict to be resolved
- Bundler 4.0.4 correctly identifies the conflict but it doesn't actually break the build

### Solution
Fixed Dockerfile to install the correct bundler version:

```dockerfile
# Before:
ENV BUNDLER_VERSION=2.5.11
RUN gem install bundler  # Installs latest (4.0.4)

# After:
ENV BUNDLER_VERSION=2.5.11
RUN gem install bundler -v ${BUNDLER_VERSION}  # Installs 2.5.11
```

**Files changed:**
- `docker/Dockerfile` (lines 38, 136)

**Verification:**
```bash
# In build logs, should see:
Successfully installed bundler-2.5.11
# Not:
Successfully installed bundler-4.0.4
```

---

## Issue 3: Tag Pointing to Old Commit

### Problem
Tag `v4.10.0-fazer-ai.15-ee` was created before the fixes were committed, so builds used old code without fixes.

### Root Cause
Tag was created at commit `ad7e4b6c4` (before fixes), but fixes were in later commits.

### Solution
Recreated tag to point to HEAD with all fixes:

```bash
git tag -f v4.10.0-fazer-ai.15-ee
git push origin v4.10.0-fazer-ai.15-ee --force
```

**Files affected:**
- Git tag `v4.10.0-fazer-ai.15-ee` (now points to commit with all fixes)

---

## Issue 4: Workflow Complexity

### Problem
Initial workflow tried to patch Dockerfile at runtime, adding complexity and potential failure points.

### Root Cause
Tried to patch bundle install command in workflow instead of fixing it directly in Dockerfile.

### Solution
Removed redundant patching step - fixes are now directly in Dockerfile:

```yaml
# Removed:
- name: Patch Dockerfile for better bundle install reliability
  run: |
    # Complex Python script...

# Kept simple:
- name: Set Chatwoot edition
  run: |
    echo -en '\nENV CW_EDITION="ee"' >> docker/Dockerfile
```

**Files changed:**
- `.github/workflows/build_custom_ee_image.yml`

---

## Build Configuration

### Final Working Configuration

**Dockerfile:**
- Bundler version: 2.5.11 (explicitly installed)
- Bundle install: With retry logic (`-r 5` with sleep retries)
- Ruby version: 3.4.4
- Rails version: 7.1.5.2

**Workflow:**
- Simple and minimal (just sets `CW_EDITION=ee`)
- No runtime patching
- Builds for linux/amd64 and linux/arm64
- Creates multi-arch manifest

**Image:**
- Tag: `v4.10.0-fazer-ai.15-ee`
- Includes all customizations baked in
- Frontend assets pre-compiled
- Ready for production

---

## Lessons Learned

1. **Pin tool versions** - Always specify exact versions, don't rely on "latest"
2. **Fix at source** - Direct fixes in Dockerfile > runtime patching
3. **Keep it simple** - Simpler workflows have fewer failure points
4. **Verify tags** - Ensure tags point to commits with all fixes
5. **Test locally** - Run `bundle install` locally to catch dependency issues early

---

## Related Documentation

- `deployment/PRODUCTION_V4.10.0_UPGRADE_GUIDE.md` - Complete upgrade guide
- `deployment/BUNDLER_VERSION_FIX.md` - Bundler version issue details
- `deployment/ROOT_CAUSE_AND_FIX.md` - Analysis of build failures
- `deployment/VERSION_COMPARISON_ANALYSIS.md` - v4.9.1 vs v4.10.0 comparison

---

**Status:** ✅ All fixes applied and tested  
**Build:** ✅ Successful  
**Image:** ✅ Available at `ghcr.io/lucouto/chatwoot.fazer.ai:v4.10.0-fazer-ai.15-ee`

# Staging: Remove Azure OpenAI Patch Volume Mount

## Summary

The Azure OpenAI customization has been removed from the `v4.9.1-fazer-ai.1-ee` build. The staging compose file needs to be updated to remove the Azure OpenAI patch volume mount.

## Changes Required

### 1. Remove Azure OpenAI Patch Volume Mount

**In `rails` service, remove:**
```yaml
- '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'
```

**In `sidekiq` service, remove:**
```yaml
- '/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb:/app/enterprise/app/services/llm/base_open_ai_service.rb:ro'
```

### 2. Fix Environment Variable Syntax

Update all environment variables to use `${VARIABLE}` instead of `{VARIABLE}`:

**Before:**
```yaml
- 'DEFAULT_LOCALE={DEFAULT_LOCALE}'
- 'SMTP_ADDRESS={SMTP_ADDRESS}'
- 'SMTP_PORT={SMTP_PORT}'
- 'SMTP_USERNAME={SMTP_USERNAME}'
- 'SMTP_PASSWORD={SMTP_PASSWORD}'
- 'MAIL_SENDER={MAIL_SENDER}'
```

**After:**
```yaml
- 'DEFAULT_LOCALE=${DEFAULT_LOCALE}'
- 'SMTP_ADDRESS=${SMTP_ADDRESS}'
- 'SMTP_PORT=${SMTP_PORT:-587}'
- 'SMTP_USERNAME=${SMTP_USERNAME}'
- 'SMTP_PASSWORD=${SMTP_PASSWORD}'
- 'MAIL_SENDER=${MAIL_SENDER}'
```

### 3. Update POSTGRES_DATABASE Environment Variable

**Before:**
```yaml
- POSTGRES_DATABASE=chatwoot_staging
```

**After:**
```yaml
- 'POSTGRES_DATABASE=${POSTGRES_DB:-chatwoot_staging}'
```

## Complete Updated Compose File

See `STAGING_COMPOSE_SECURE.yaml` for the complete updated compose file with all changes applied.

## Verification Steps

After updating the compose file:

1. **Stop the services:**
   ```bash
   docker-compose down
   ```

2. **Update the compose file** with the changes above

3. **Start the services:**
   ```bash
   docker-compose up -d
   ```

4. **Verify the rails service starts without the Azure patch:**
   ```bash
   docker-compose logs rails | grep -i "azure\|openai" | head -20
   ```
   (Should return no results)

5. **Verify the sidekiq service starts without the Azure patch:**
   ```bash
   docker-compose logs sidekiq | grep -i "azure\|openai" | head -20
   ```
   (Should return no results)

## What Remains

The following customizations are still mounted as volumes (as expected for staging):

✅ **Kept (still using volume mounts in staging):**
- `automationHelper.js` - Custom automation filters
- `operators.js` - Custom automation operators
- `filter_service.rb` - Custom filter service backend
- `show.html.erb` - Super admin settings view
- `99_fix_pricing_plan_quantity.rb` - Pricing plan fix

❌ **Removed:**
- `base_open_ai_service.rb` - Azure OpenAI patch (no longer needed)

## Notes

- The Azure OpenAI patch file (`/opt/chatwoot-patches/enterprise/app/services/llm/base_open_ai_service.rb`) can be deleted from the server, but it's not required - the volume mount removal is sufficient.
- The `v4.9.1-fazer-ai.1-ee` image no longer contains Azure OpenAI customizations - it matches the official Chatwoot v4.9.1 code for OpenAI services.
- Environment variables are now properly using `${VAR}` syntax for consistency and correct variable substitution.


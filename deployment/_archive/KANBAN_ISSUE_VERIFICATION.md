# Kanban Integration Issue - Verification Report

## Issue Summary
Kanban fails inside Chatwoot because Chatwoot's API returns 500 on:
```
GET /api/v1/accounts/1/inboxes
```

Error: `undefined method 'use_internal_host?' for an instance of Channel::Whatsapp`

## Code Verification (Current Codebase)

### ✅ Method EXISTS in Codebase
**File**: `app/models/channel/whatsapp.rb` (lines 69-71)
```ruby
def use_internal_host?
  false
end
```

### ✅ Method is Being Called
**File**: `app/models/inbox.rb` (line 191)
```ruby
when 'Channel::Whatsapp'
  host = ENV.fetch('INTERNAL_HOST_URL', nil) if channel.use_internal_host?
  "#{host}/webhooks/whatsapp/#{channel.phone_number}"
```

### ✅ API Endpoint Uses This Method
**File**: `app/views/api/v1/models/_inbox.json.jbuilder` (line 17)
```ruby
json.callback_webhook_url resource.callback_webhook_url
```

When serializing inboxes, `callback_webhook_url` is called, which calls `channel.use_internal_host?` for WhatsApp channels.

## Hypothesis

The method **exists in the current codebase** but may be **missing in the deployed Docker image** (`v4.10.0-fazer-ai.15-ee`). This could happen if:

1. The Docker image was built from code that didn't include this method
2. The method was added after the image was built
3. There's a version mismatch between the base Chatwoot version and customizations

## Verification Steps

### Option 1: Quick Production Check (Recommended)
Run this on your production server:

```bash
# Find rails container
RAILS_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "rails|chatwoot" | grep -v sidekiq | head -1)

# Check if method exists
docker exec "$RAILS_CONTAINER" bundle exec rails runner "
  channel = Channel::Whatsapp.first
  if channel.nil?
    puts 'No WhatsApp channels found'
  elsif channel.respond_to?(:use_internal_host?)
    puts '✅ Method EXISTS'
  else
    puts '❌ Method MISSING - Issue confirmed!'
  end
"
```

### Option 2: Test the API Endpoint Directly
```bash
# Test the failing endpoint
curl -H "api_access_token: YOUR_TOKEN" \
  https://chatwoot.cheminneuf.community/api/v1/accounts/1/inboxes

# If it returns 500, check logs:
docker logs "$RAILS_CONTAINER" --tail 100 | grep -i "use_internal_host"
```

### Option 3: Use Verification Script
```bash
bash deployment/verify_kanban_issue.sh
```

## If Issue is Confirmed

If the method is missing in production, apply one of these fixes:

### Fix A: Add Missing Method (Recommended)
**File**: `app/models/channel/whatsapp.rb`

The method already exists in the codebase. If it's missing in production:
1. Ensure the method is present in the deployed image
2. Or add it as a patch volume mount (quick fix)

### Fix B: Make callback_webhook_url Defensive
**File**: `app/models/inbox.rb` (line 191)

```ruby
when 'Channel::Whatsapp'
  host = ENV.fetch('INTERNAL_HOST_URL', nil) if channel.respond_to?(:use_internal_host?) && channel.use_internal_host?
  "#{host}/webhooks/whatsapp/#{channel.phone_number}"
```

This guards against missing method and prevents crash.

## Next Steps

1. ✅ **Verify** if the issue exists in production (run Option 1 above)
2. ✅ **If confirmed**, determine if:
   - Fix needed in codebase (rebuild image)
   - Fix needed as patch (volume mount)
   - Fix needed defensively (guard the call)
3. ✅ **Apply fix** based on urgency and deployment strategy

## Notes

- The method exists in the current codebase at line 69-71 of `app/models/channel/whatsapp.rb`
- If production image is missing it, this is likely a build/sync issue
- The defensive fix (Fix B) would work immediately without rebuilding

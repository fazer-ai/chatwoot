#!/bin/bash
# Diagnostic script to verify the Kanban integration issue
# This checks if use_internal_host? method exists on Channel::Whatsapp in production

echo "=== Verifying Kanban Integration Issue ==="
echo ""

# Find rails container
RAILS_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "rails|chatwoot" | grep -v sidekiq | head -1)

if [ -z "$RAILS_CONTAINER" ]; then
  echo "❌ Could not find rails container"
  docker ps --format "{{.Names}}\t{{.Image}}"
  exit 1
fi

echo "Found container: $RAILS_CONTAINER"
echo ""

# Check if method exists in Channel::Whatsapp
echo "=== Checking if use_internal_host? method exists ==="
docker exec "$RAILS_CONTAINER" bundle exec rails runner "
  begin
    channel = Channel::Whatsapp.first
    if channel.nil?
      puts '⚠️  No WhatsApp channels found. Cannot test.'
      exit 0
    end
    
    if channel.respond_to?(:use_internal_host?)
      puts '✅ Method use_internal_host? EXISTS on Channel::Whatsapp'
      puts \"   Returns: #{channel.use_internal_host?}\"
    else
      puts '❌ Method use_internal_host? DOES NOT EXIST on Channel::Whatsapp'
      puts '   This confirms the issue exists!'
      exit 1
    end
  rescue => e
    puts \"❌ Error checking method: #{e.message}\"
    puts e.backtrace.first(3).join(\"\\n\")
    exit 1
  end
"

echo ""
echo "=== Testing callback_webhook_url on Inbox with WhatsApp channel ==="
docker exec "$RAILS_CONTAINER" bundle exec rails runner "
  begin
    whatsapp_inbox = Inbox.joins(:channel).where(channels: { type: 'Channel::Whatsapp' }).first
    if whatsapp_inbox.nil?
      puts '⚠️  No WhatsApp inboxes found. Cannot test.'
      exit 0
    end
    
    puts \"Testing inbox ID: #{whatsapp_inbox.id}\"
    url = whatsapp_inbox.callback_webhook_url
    puts \"✅ callback_webhook_url works: #{url}\"
  rescue => e
    puts \"❌ Error in callback_webhook_url: #{e.class.name}\"
    puts \"   Message: #{e.message}\"
    if e.message.include?('use_internal_host?')
      puts ''
      puts '   ⚠️  CONFIRMED: The issue exists!'
      puts '   The method use_internal_host? is missing from Channel::Whatsapp'
    end
    puts e.backtrace.first(5).join(\"\\n\")
    exit 1
  end
"

echo ""
echo "=== Testing API endpoint /api/v1/accounts/:id/inboxes ==="
docker exec "$RAILS_CONTAINER" bundle exec rails runner "
  begin
    account = Account.first
    if account.nil?
      puts '⚠️  No accounts found. Cannot test.'
      exit 0
    end
    
    inboxes = account.inboxes.includes(:channel)
    whatsapp_count = inboxes.count { |i| i.channel_type == 'Channel::Whatsapp' }
    puts \"Account ID: #{account.id}\"
    puts \"Total inboxes: #{inboxes.count}\"
    puts \"WhatsApp inboxes: #{whatsapp_count}\"
    
    if whatsapp_count > 0
      puts ''
      puts '⚠️  WhatsApp inboxes exist. The API endpoint will likely fail.'
      puts '   Try accessing: GET /api/v1/accounts/#{account.id}/inboxes'
    else
      puts ''
      puts 'ℹ️  No WhatsApp inboxes found. Issue may not manifest without them.'
    end
  rescue => e
    puts \"❌ Error: #{e.message}\"
    exit 1
  end
"

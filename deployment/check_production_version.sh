#!/bin/bash
# Check production version - works with docker-compose, docker compose, or direct docker commands

echo "=== Checking Production Version ==="
echo ""

# Try different methods to find rails container
RAILS_CONTAINER=""

# Method 1: Try docker compose (v2)
if command -v docker > /dev/null 2>&1; then
  if docker compose version > /dev/null 2>&1; then
    echo "Using: docker compose (v2)"
    RAILS_CONTAINER=$(docker compose ps rails --format json 2>/dev/null | grep -o '"Name":"[^"]*' | cut -d'"' -f4 | head -1)
    if [ -n "$RAILS_CONTAINER" ]; then
      echo "Found container: $RAILS_CONTAINER"
      echo ""
      docker compose exec rails bundle exec rails runner "puts ChatwootApp.config.version"
      exit 0
    fi
  fi
fi

# Method 2: Find rails container directly
RAILS_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "rails|chatwoot" | grep -v sidekiq | head -1)

if [ -z "$RAILS_CONTAINER" ]; then
  echo "❌ Could not find rails container"
  echo ""
  echo "Available containers:"
  docker ps --format "{{.Names}}\t{{.Image}}"
  echo ""
  echo "Please run:"
  echo "  docker exec <container-name> bundle exec rails runner \"puts ChatwootApp.config.version\""
  exit 1
fi

echo "Found container: $RAILS_CONTAINER"
echo ""

# Method 3: Direct docker exec
docker exec "$RAILS_CONTAINER" bundle exec rails runner "puts ChatwootApp.config.version"

# Also show image info
echo ""
echo "Container image:"
docker ps --format "{{.Names}}\t{{.Image}}" | grep "$RAILS_CONTAINER"

#!/bin/bash
# Copy patch files to production server
# Usage options:
#   1. From local repository to production (via SSH)
#   2. From staging to production (via SSH)

set -e

PRODUCTION_HOST="${PRODUCTION_HOST:-azureuser@your-production-server.com}"
PRODUCTION_PATCHES_DIR="/opt/chatwoot-patches"
LOCAL_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Copy Patch Files to Production ==="
echo ""

# Check if we should copy from local repo or staging
echo "Choose source:"
echo "1) Copy from local repository (this repo)"
echo "2) Copy from staging server"
read -p "Enter choice [1 or 2]: " SOURCE_CHOICE

case $SOURCE_CHOICE in
  1)
    echo ""
    echo "Copying from local repository to production..."
    echo "Production server: $PRODUCTION_HOST"
    echo ""
    
    # Create directory structure on production
    ssh "$PRODUCTION_HOST" "mkdir -p $PRODUCTION_PATCHES_DIR/app/services"
    ssh "$PRODUCTION_HOST" "mkdir -p $PRODUCTION_PATCHES_DIR/app/views/super_admin/settings"
    ssh "$PRODUCTION_HOST" "mkdir -p $PRODUCTION_PATCHES_DIR/config/initializers"
    ssh "$PRODUCTION_HOST" "mkdir -p $PRODUCTION_PATCHES_DIR/enterprise/app/services/llm"
    
    # Copy files
    echo "Copying filter_service.rb..."
    scp "$LOCAL_REPO_DIR/app/services/filter_service.rb" \
        "$PRODUCTION_HOST:$PRODUCTION_PATCHES_DIR/app/services/filter_service.rb"
    
    echo "Copying show.html.erb..."
    scp "$LOCAL_REPO_DIR/app/views/super_admin/settings/show.html.erb" \
        "$PRODUCTION_HOST:$PRODUCTION_PATCHES_DIR/app/views/super_admin/settings/show.html.erb"
    
    echo "Copying 99_fix_pricing_plan_quantity.rb..."
    scp "$LOCAL_REPO_DIR/config/initializers/99_fix_pricing_plan_quantity.rb" \
        "$PRODUCTION_HOST:$PRODUCTION_PATCHES_DIR/config/initializers/99_fix_pricing_plan_quantity.rb"
    
    echo "Copying base_open_ai_service.rb..."
    if [ -f "$LOCAL_REPO_DIR/enterprise/app/services/llm/base_open_ai_service.rb" ]; then
      scp "$LOCAL_REPO_DIR/enterprise/app/services/llm/base_open_ai_service.rb" \
          "$PRODUCTION_HOST:$PRODUCTION_PATCHES_DIR/enterprise/app/services/llm/base_open_ai_service.rb"
    else
      echo "⚠️  base_open_ai_service.rb not found in local repo (may not exist if not using enterprise)"
    fi
    
    echo ""
    echo "✅ Files copied successfully!"
    ;;
    
  2)
    echo ""
    read -p "Enter staging server (e.g., azureuser@staging-server.com): " STAGING_HOST
    
    if [ -z "$STAGING_HOST" ]; then
      echo "❌ Staging host not provided"
      exit 1
    fi
    
    echo ""
    echo "Copying from staging to production..."
    echo "Staging server: $STAGING_HOST"
    echo "Production server: $PRODUCTION_HOST"
    echo ""
    
    # Create directory structure on production
    ssh "$PRODUCTION_HOST" "mkdir -p $PRODUCTION_PATCHES_DIR/app/services"
    ssh "$PRODUCTION_HOST" "mkdir -p $PRODUCTION_PATCHES_DIR/app/views/super_admin/settings"
    ssh "$PRODUCTION_HOST" "mkdir -p $PRODUCTION_PATCHES_DIR/config/initializers"
    ssh "$PRODUCTION_HOST" "mkdir -p $PRODUCTION_PATCHES_DIR/enterprise/app/services/llm"
    
    # Copy files from staging to production
    echo "Copying filter_service.rb..."
    ssh "$STAGING_HOST" "cat $PRODUCTION_PATCHES_DIR/app/services/filter_service.rb" | \
        ssh "$PRODUCTION_HOST" "cat > $PRODUCTION_PATCHES_DIR/app/services/filter_service.rb"
    
    echo "Copying show.html.erb..."
    ssh "$STAGING_HOST" "cat $PRODUCTION_PATCHES_DIR/app/views/super_admin/settings/show.html.erb" | \
        ssh "$PRODUCTION_HOST" "cat > $PRODUCTION_PATCHES_DIR/app/views/super_admin/settings/show.html.erb"
    
    echo "Copying 99_fix_pricing_plan_quantity.rb..."
    ssh "$STAGING_HOST" "cat $PRODUCTION_PATCHES_DIR/config/initializers/99_fix_pricing_plan_quantity.rb" | \
        ssh "$PRODUCTION_HOST" "cat > $PRODUCTION_PATCHES_DIR/config/initializers/99_fix_pricing_plan_quantity.rb"
    
    echo "Copying base_open_ai_service.rb..."
    ssh "$STAGING_HOST" "cat $PRODUCTION_PATCHES_DIR/enterprise/app/services/llm/base_open_ai_service.rb" | \
        ssh "$PRODUCTION_HOST" "cat > $PRODUCTION_PATCHES_DIR/enterprise/app/services/llm/base_open_ai_service.rb" || \
        echo "⚠️  base_open_ai_service.rb not found on staging (may not exist)"
    
    echo ""
    echo "✅ Files copied successfully!"
    ;;
    
  *)
    echo "❌ Invalid choice"
    exit 1
    ;;
esac

echo ""
echo "Verifying files on production..."
ssh "$PRODUCTION_HOST" "bash -s" < "$(dirname "${BASH_SOURCE[0]}")/check_production_patches.sh"

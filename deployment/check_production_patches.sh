#!/bin/bash
# Check if patch files exist on production server
# Usage: Run this script on your production server

set -e

echo "Checking for patch files in /opt/chatwoot-patches/..."
echo ""

PATCHES_DIR="/opt/chatwoot-patches"
FILES_TO_CHECK=(
  "app/services/filter_service.rb"
  "app/views/super_admin/settings/show.html.erb"
  "config/initializers/99_fix_pricing_plan_quantity.rb"
  "enterprise/app/services/llm/base_open_ai_service.rb"
)

ALL_EXIST=true

# Check if patches directory exists
if [ ! -d "$PATCHES_DIR" ]; then
  echo "❌ Patches directory does not exist: $PATCHES_DIR"
  echo "   Creating directory structure..."
  mkdir -p "$PATCHES_DIR/app/services"
  mkdir -p "$PATCHES_DIR/app/views/super_admin/settings"
  mkdir -p "$PATCHES_DIR/config/initializers"
  mkdir -p "$PATCHES_DIR/enterprise/app/services/llm"
  echo "✅ Directory structure created"
  echo ""
  ALL_EXIST=false
else
  echo "✅ Patches directory exists: $PATCHES_DIR"
  echo ""
fi

# Check each file
for file in "${FILES_TO_CHECK[@]}"; do
  full_path="$PATCHES_DIR/$file"
  if [ -f "$full_path" ]; then
    size=$(ls -lh "$full_path" | awk '{print $5}')
    echo "✅ $file ($size)"
  else
    echo "❌ $file (MISSING)"
    ALL_EXIST=false
  fi
done

echo ""

if [ "$ALL_EXIST" = true ]; then
  echo "✅ All patch files are present!"
  exit 0
else
  echo "❌ Some patch files are missing"
  echo ""
  echo "To copy missing files, see: deployment/copy_patches_to_production.sh"
  exit 1
fi

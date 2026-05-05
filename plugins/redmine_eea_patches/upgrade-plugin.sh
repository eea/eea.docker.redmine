#!/bin/bash
#
# Plugin Upgrade Helper Script
# Usage: ./upgrade-plugin.sh <plugin_name> <new_version>
#
# Example: ./upgrade-plugin.sh redmine_contacts_helpdesk 4.3.0

set -euo pipefail

PLUGIN_NAME=${1:-}
NEW_VERSION=${2:-}
PATCHES_DIR="plugins/redmine_eea_patches"

if [ -z "$PLUGIN_NAME" ] || [ -z "$NEW_VERSION" ]; then
  echo "Usage: $0 <plugin_name> <new_version>"
  echo "Example: $0 redmine_contacts_helpdesk 4.3.0"
  exit 1
fi

echo "=========================================="
echo "Plugin Upgrade Helper"
echo "=========================================="
echo "Plugin: $PLUGIN_NAME"
echo "New Version: $NEW_VERSION"
echo ""

# Step 1: Check if we have patches for this plugin
if [ ! -d "$PATCHES_DIR/app/views" ] && [ ! -f "$PATCHES_DIR/init.rb" ]; then
  echo "❌ Error: EEA Patches plugin not found in $PATCHES_DIR"
  exit 1
fi

echo "Step 1: Checking current patches..."
PATCHED_FILES=$(find $PATCHES_DIR/app/views -name "*.erb" -not -name "*.original" 2>/dev/null || true)
if [ -z "$PATCHED_FILES" ]; then
  echo "  No view patches found"
else
  echo "  Found patched view files:"
  echo "$PATCHED_FILES" | sed 's/^/    /'
fi
echo ""

# Step 2: Download new plugin version (manual step)
echo "Step 2: Download Plugin"
echo "  ⚠️  Manual step required:"
echo "  1. Download ${PLUGIN_NAME}-${NEW_VERSION}-pro.zip"
echo "  2. Place it in: .local-artifacts/redmineup/plugins/"
echo "  3. Press Enter when ready"
read -p "  Press Enter to continue..."
echo ""

# Step 3: Extract and compare
echo "Step 3: Comparing versions..."
PLUGIN_ZIP=".local-artifacts/redmineup/plugins/${PLUGIN_NAME}-${NEW_VERSION}-pro.zip"

if [ ! -f "$PLUGIN_ZIP" ]; then
  echo "  ❌ Plugin zip not found: $PLUGIN_ZIP"
  exit 1
fi

# Extract to temp
TEMP_DIR=$(mktemp -d)
unzip -q "$PLUGIN_ZIP" -d "$TEMP_DIR"

echo "  Extracted to: $TEMP_DIR"
echo ""

# Step 4: Check each patched file
echo "Step 4: Checking for conflicts..."
CONFLICTS=0

for patched_file in $PATCHED_FILES; do
  # Get relative path from patches dir
  rel_path=${patched_file#$PATCHES_DIR/app/views/}
  original_file="plugins/$PLUGIN_NAME/app/views/$rel_path"
  new_file="$TEMP_DIR/$PLUGIN_NAME/app/views/$rel_path"
  
  if [ ! -f "$new_file" ]; then
    echo "  ⚠️  File moved or deleted: $rel_path"
    CONFLICTS=$((CONFLICTS + 1))
    continue
  fi
  
  if diff -q "$original_file" "$new_file" > /dev/null 2>&1; then
    echo "  ✅ No changes: $rel_path"
  else
    echo "  ⚠️  CHANGED: $rel_path"
    echo "     Differences:"
    diff -u "$original_file" "$new_file" | head -20 | sed 's/^/       /'
    CONFLICTS=$((CONFLICTS + 1))
  fi
done

echo ""

# Step 5: Provide guidance
echo "Step 5: Summary"
if [ $CONFLICTS -eq 0 ]; then
  echo "  ✅ No conflicts detected!"
  echo "  You can safely:"
  echo "    1. Update addons.cfg to version $NEW_VERSION"
  echo "    2. Rebuild Docker image"
  echo "    3. Deploy"
else
  echo "  ⚠️  $CONFLICTS file(s) changed"
  echo "  Action required:"
  echo "    1. Review the differences above"
  echo "    2. Update your patched files to match new structure"
  echo "    3. Re-apply your optimizations"
  echo "    4. Test thoroughly"
  echo ""
  echo "  See PLUGIN_UPGRADE_GUIDE.md for detailed instructions"
fi

echo ""
echo "Step 6: Cleanup"
read -p "  Delete temp directory $TEMP_DIR? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [ -z "$REPLY" ]; then
  rm -rf "$TEMP_DIR"
  echo "  Cleaned up"
else
  echo "  Temp directory kept at: $TEMP_DIR"
fi

echo ""
echo "=========================================="
echo "Upgrade check complete"
echo "=========================================="

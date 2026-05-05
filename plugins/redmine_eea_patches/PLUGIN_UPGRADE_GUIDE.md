# Plugin Upgrade Management

## The Challenge

When Redmine plugins (redmine_contacts_helpdesk, redmine_crm, etc.) are upgraded, your patches may break or become incompatible. This guide shows how to manage upgrades systematically.

---

## The Core Problem

```
Original Plugin v4.2.6
├── View: _helpdesk_tickets.html.erb (Line 42)
└── Your Patch: Modified Line 42

Upgraded Plugin v4.3.0
├── View: _helpdesk_tickets.html.erb (Line 42 CHANGED!)
└── Your Patch: Still expecting old Line 42

RESULT: Conflict, broken functionality, or silent failures
```

---

## Upgrade Management Strategy

### Strategy 1: Version Pinning (Conservative)

**Keep plugin versions fixed until patches are verified.**

**addons.cfg:**
```
# Pin to known working version
plugin:redmine_contacts_helpdesk:4.2.6-pro:zip
plugin:redmine_crm:4.4.3-pro:zip
```

**When to upgrade:**
- Security vulnerability in current version
- Critical bug fixed in new version
- New features needed
- You have time to test patches

**Pros:**
- ✅ Stable, predictable
- ✅ No surprise breakages
- ✅ Patches always work

**Cons:**
- ❌ Miss security updates
- ❌ Technical debt accumulates
- ❌ Large upgrade jumps

**Best for:** Production environments where stability > features

---

### Strategy 2: Continuous Integration Testing (Aggressive)

**Automatically test patches against latest plugin versions.**

**CI Pipeline:**
```yaml
# .github/workflows/plugin-upgrade-test.yml
name: Plugin Compatibility Test

on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly
  workflow_dispatch:

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        plugin_version:
          - "4.2.6-pro"
          - "4.3.0-pro"  # Latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Test Patches
        run: |
          docker build \
            --build-arg HELPDESK_VERSION=${{ matrix.plugin_version }} \
            -t redmine:test .
          
          docker run redmine:test rails test:plugins:redmine_eea_patches
```

**Pros:**
- ✅ Immediate notification of breakages
- ✅ Can track multiple versions
- ✅ Automated testing

**Cons:**
- ❌ CI infrastructure required
- ❌ False positives
- ❌ Maintenance overhead

**Best for:** Teams with mature DevOps practices

---

### Strategy 3: Diff-Based Patch Management (Recommended)

**Track differences between original and patched files.**

**Structure:**
```
plugins/redmine_eea_patches/
├── patches/
│   ├── redmine_contacts_helpdesk/
│   │   ├── 4.2.6/
│   │   │   └── _helpdesk_tickets.html.erb.patch
│   │   ├── 4.3.0/
│   │   │   └── _helpdesk_tickets.html.erb.patch
│   │   └── manifest.json
│   └── redmine_crm/
│       └── 4.4.3/
│           └── _list.html.erb.patch
```

**Patch File Format (Unified Diff):**
```diff
--- a/plugins/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb
+++ b/plugins/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb
@@ -2,8 +2,8 @@
 <% if User.current.allowed_to?(:view_helpdesk_tickets, @project) %>
-    <% if tickets = HelpdeskTicket.includes(:issue => [:project]).where(:projects => {:id => @project}) %>
-      <% customers = Contact.includes(:tickets => :project).where(:projects => {:id => @project}) %>
+    <% ticket_count = HelpdeskTicket.joins(:issue).where(:issues => { :project_id => @project.id }).count %>
+    <% customer_count = HelpdeskTicket.joins(:issue).where(:issues => { :project_id => @project.id }).where.not(:contact_id => nil).distinct.count(:contact_id) %>
       <h3><%= l(:label_helpdesk_ticket_plural) %></h3>
-      <p><span class="icon icon-helpdesk"><%= sprite_icon('icon-helpdesk', l(:text_helpdesk_ticket_count, :count => tickets.count), plugin: :redmine_contacts_helpdesk) %></span></p>
-      <p><span class="icon icon-company-contact"><%= sprite_icon('user', l(:text_helpdesk_customer_count, :count => customers.count)) %> </span></p>
+      <p><span class="icon icon-helpdesk"><%= sprite_icon('icon-helpdesk', l(:text_helpdesk_ticket_count, :count => ticket_count), plugin: :redmine_contacts_helpdesk) %></span></p>
+      <p><span class="icon icon-company-contact"><%= sprite_icon('user', l(:text_helpdesk_customer_count, :count => customer_count)) %></span></p>
```

**Apply Patch Script:**
```bash
#!/bin/bash
# apply-patches.sh

PLUGIN=$1
VERSION=$2

for patch in plugins/redmine_eea_patches/patches/${PLUGIN}/${VERSION}/*.patch; do
  echo "Applying: $patch"
  patch -p1 < "$patch" || {
    echo "ERROR: Failed to apply $patch"
    echo "Original file may have changed significantly"
    exit 1
  }
done
```

**Pros:**
- ✅ Version-specific patches
- ✅ Clear what changed
- ✅ Standard diff format
- ✅ Easy to review

**Cons:**
- ❌ Patches can fail if context changes
- ❌ Need to regenerate for each version
- ❌ Git knowledge required

**Best for:** Most teams - good balance of control and automation

---

## Upgrade Workflow (Step-by-Step)

### Phase 1: Preparation

**1. Check current state**
```bash
# Document current versions
kubectl exec <pod> -n taskman -c taskman-redmine -- ls plugins/

# Check which files are patched
git status
```

**2. Review upstream changelog**
```bash
# Download new plugin version
wget https://redmineup.com/downloads/redmine_contacts_helpdesk-4.3.0-pro.zip

# Extract and compare
unzip redmine_contacts_helpdesk-4.3.0-pro.zip -d /tmp/new_version

# Find changed files
diff -r plugins/redmine_contacts_helpdesk /tmp/new_version/redmine_contacts_helpdesk
```

**3. Assess impact**
```bash
# Check if patched files changed
diff plugins/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb \
     /tmp/new_version/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb

# Exit code 0 = no changes (safe to upgrade)
# Exit code 1 = changes (need to update patch)
```

---

### Phase 2: Update Patches

**If patched files changed:**

**Step 1: Extract original new version**
```bash
cp /tmp/new_version/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb \
   plugins/redmine_eea_patches/app/views/projects/_helpdesk_tickets.html.erb.v4.3.0.original
```

**Step 2: Re-apply optimization to new version**
```bash
# Create new patched version
# Option A: Manual edit
cp plugins/redmine_eea_patches/app/views/projects/_helpdesk_tickets.html.erb.v4.3.0.original \
   plugins/redmine_eea_patches/app/views/projects/_helpdesk_tickets.html.erb

# Edit and apply same optimizations
vim plugins/redmine_eea_patches/app/views/projects/_helpdesk_tickets.html.erb

# Option B: Sed/Script if changes are consistent
sed -i 's/includes(:issue => \[:project\])/joins(:issue)/g' \
  plugins/redmine_eea_patches/app/views/projects/_helpdesk_tickets.html.erb
```

**Step 3: Generate new diff**
```bash
diff -u \
  plugins/redmine_eea_patches/app/views/projects/_helpdesk_tickets.html.erb.v4.3.0.original \
  plugins/redmine_eea_patches/app/views/projects/_helpdesk_tickets.html.erb \
  > plugins/redmine_eea_patches/patches/redmine_contacts_helpdesk/4.3.0/_helpdesk_tickets.html.erb.patch
```

---

### Phase 3: Testing

**1. Local testing**
```bash
docker build -t redmine:test .
docker run -p 3000:3000 redmine:test

# Test in browser
open http://localhost:3000/projects/nanyt
```

**2. Automated tests**
```bash
docker run redmine:test rails test:plugins:redmine_eea_patches
```

**3. Staging deployment**
```bash
kubectl apply -f k8s/staging/
kubectl set image deployment/taskman-redmine-staging taskman-redmine=redmine:test
```

**4. Validation checklist**
- [ ] Page loads in <5 seconds
- [ ] Ticket counts correct
- [ ] No JavaScript errors
- [ ] No 500 errors in logs
- [ ] All tests pass

---

### Phase 4: Production Deployment

**1. Update CHANGELOG**
```markdown
## [1.2.0] - 2026-05-01

### Changed
- Updated for redmine_contacts_helpdesk 4.3.0
- Re-applied performance optimization to new view structure
- Changed: Line 45 now uses `joins(:issue)` instead of deprecated syntax

### Compatibility
- redmine_contacts_helpdesk: 4.3.0 (was 4.2.6)
```

**2. Update version**
```ruby
# init.rb
version '1.2.0'  # Bumped for plugin upgrade
```

**3. Deploy**
```bash
git add .
git commit -m "chore: Update patches for helpdesk plugin v4.3.0"
git push

# Build and deploy
docker build -t eeacms/redmine:v1.2.0 .
docker push eeacms/redmine:v1.2.0

kubectl set image deployment/taskman-redmine taskman-redmine=eeacms/redmine:v1.2.0
```

**4. Monitor**
```bash
# Watch for errors
kubectl logs -f deployment/taskman-redmine -n taskman --tail=100

# Check response times
kubectl exec <nginx-pod> -n taskman -- tail -f /var/log/nginx/access.log | grep nanyt
```

---

## Automated Detection Script

Create a script that detects when upstream changes:

```ruby
#!/usr/bin/env ruby
# check-plugin-updates.rb

require 'json'
require 'net/http'

PLUGINS = {
  'redmine_contacts_helpdesk' => {
    current: '4.2.6-pro',
    url: 'https://redmineup.com/api/versions/helpdesk',
    patched_files: [
      'app/views/projects/_helpdesk_tickets.html.erb'
    ]
  },
  'redmine_crm' => {
    current: '4.4.3-pro',
    url: 'https://redmineup.com/api/versions/crm',
    patched_files: [
      'app/views/contacts/_list.html.erb'
    ]
  }
}

PLUGINS.each do |name, config|
  puts "\nChecking #{name}..."
  puts "  Current: #{config[:current]}"
  
  # Check for new version (example API)
  begin
    uri = URI(config[:url])
    response = Net::HTTP.get(uri)
    latest = JSON.parse(response)['latest_version']
    
    puts "  Latest: #{latest}"
    
    if latest != config[:current]
      puts "  ⚠️  NEW VERSION AVAILABLE!"
      puts "  Patched files: #{config[:patched_files].join(', ')}"
      puts "  Action: Download and check for conflicts"
    else
      puts "  ✓ Up to date"
    end
  rescue => e
    puts "  ✗ Error checking: #{e.message}"
  end
end
```

---

## Conflict Resolution Guide

### Scenario 1: Minor Changes (Context Lines Changed)

**Problem:** Patch fails because surrounding lines changed

**Solution:** Update patch context

```bash
# Apply with fuzz (loose matching)
patch -p1 --fuzz=3 < file.patch

# If still fails, manually merge
cp new_original_file new_patched_file
vim new_patched_file  # Re-apply optimizations
```

### Scenario 2: Major Refactoring (File Completely Changed)

**Problem:** Whole file structure changed

**Solution:** Rewrite patch from scratch

```bash
# 1. Study new version to understand changes
# 2. Identify where optimization should go
# 3. Apply optimization to new structure
# 4. Test thoroughly
```

### Scenario 3: Feature Removed (Patched feature no longer exists)

**Problem:** Your patch targets a removed feature

**Solution:** Evaluate if patch still needed

```bash
# Check if the slow query still exists
grep -r "includes.*helpdesk_ticket" plugins/redmine_contacts_helpdesk/

# If not found, feature was refactored
# Remove patch and test if performance is now acceptable
```

---

## Version Compatibility Matrix

Maintain a compatibility matrix:

```markdown
# Plugin Compatibility

| Plugin | Versions Supported | Notes |
|--------|-------------------|-------|
| redmine_contacts_helpdesk | 4.2.6 - 4.3.0 | Tested with 4.2.6, 4.3.0 |
| redmine_crm | 4.4.3 | Only version tested |
| redmine_agile | Not patched | No conflicts |

## Known Incompatibilities

- redmine_contacts_helpdesk 4.4.0+: View structure changed significantly (see Issue #123)
```

---

## Rollback Strategy

If upgrade fails:

**Quick rollback:**
```bash
# Revert to previous image
kubectl rollout undo deployment/taskman-redmine

# Or deploy previous version explicitly
kubectl set image deployment/taskman-redmine taskman-redmine=eeacms/redmine:v1.1.0
```

**Full rollback:**
```bash
# Disable the patch plugin
kubectl exec <pod> -n taskman -c taskman-redmine -- \
  mv plugins/redmine_eea_patches plugins/redmine_eea_patches.disabled

# Restart
kubectl rollout restart deployment/taskman-redmine
```

---

## Best Practices

### 1. Keep Originals

Always keep original files for reference:
```
_helpdesk_tickets.html.erb.v4.2.6.original
_helpdesk_tickets.html.erb.v4.3.0.original
```

### 2. Document Changes

In your patched file, comment what you changed:
```erb
<%# EEA PATCH: Replaced includes() with joins() for performance %>
<%# See: https://github.com/eea/eea.docker.redmine/issues/123 %>
<% ticket_count = HelpdeskTicket.joins(:issue)... %>
```

### 3. Test on Staging First

Never deploy to production without staging testing

### 4. Have Rollback Ready

Always be able to revert in <5 minutes

### 5. Monitor After Deploy

Watch logs and metrics for 24-48 hours post-deploy

---

## Summary

**The Golden Rule:** 
> Never upgrade plugins blindly. Always check if your patches conflict with new versions.

**Recommended Workflow:**
1. Pin versions in production
2. Test new versions in staging
3. Update patches if files changed
4. Document compatibility
5. Deploy with monitoring
6. Have rollback ready

**Time Investment:**
- No changes: 5 minutes (test and deploy)
- Minor changes: 30 minutes (update patch)
- Major changes: 2-4 hours (rewrite and test)

**Tooling:**
- Use diffs to track changes
- Automate testing where possible
- Keep compatibility matrix
- Document everything

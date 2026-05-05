# Multi-Patch Plugin Structure Guide

## Overview

As you add more patches, organization becomes critical. This guide shows how to structure the `redmine_eea_patches` plugin to handle multiple patches cleanly.

---

## Recommended Directory Structure

```
plugins/redmine_eea_patches/
├── init.rb                                    # Main entry point
├── README.md                                  # Overview
├── CHANGELOG.md                               # Version history
├── PATCHES_INDEX.md                           # Catalog of all patches
│
├── app/
│   ├── controllers/
│   │   └── patches/
│   │       └── issues_controller_patch.rb     # Controller patches
│   │
│   ├── models/
│   │   └── patches/
│   │       ├── issue_patch.rb                 # Model patches
│   │       └── helpdesk_ticket_patch.rb
│   │
│   ├── views/
│   │   ├── helpdesk/
│   │   │   └── _performance_fix.html.erb      # Organize by feature
│   │   ├── projects/
│   │   │   ├── _helpdesk_tickets.html.erb     # ← Your current patch
│   │   │   └── _helpdesk_tickets.html.erb.original
│   │   └── issues/
│   │       └── _sidebar.html.erb
│   │
│   └── helpers/
│       └── patches/
│           └── application_helper_patch.rb
│
├── config/
│   └── routes.rb                              # Custom routes (if needed)
│
├── db/
│   └── migrate/
│       ├── 001_create_project_helpdesk_stats.rb
│       └── 002_add_issue_counter_cache.rb
│
├── lib/
│   ├── redmine_eea_patches.rb                 # Loader
│   ├── patches.rb                             # Patch registration
│   │
│   └── patches/
│       ├── base_patch.rb                      # Base class for patches
│       ├── helpdesk_performance_patch.rb      # Feature-based grouping
│       ├── mailer_timeout_patch.rb
│       └── agile_board_fix.rb
│
├── test/
│   ├── test_helper.rb
│   ├── fixtures/
│   │   └── helpdesk_tickets.yml
│   ├── unit/
│   │   └── patches/
│   │       └── helpdesk_performance_test.rb
│   └── integration/
│       └── patches_integration_test.rb
│
└── docs/
    ├── ARCHITECTURE.md
    ├── DEPLOYMENT.md
    └── TROUBLESHOOTING.md
```

---

## Organization Strategies

### Strategy 1: By Component Type (Recommended)

Group patches by what they modify:

```
app/
  views/           # View overrides
  models/          # Model patches
  controllers/     # Controller patches
  helpers/         # Helper patches

lib/patches/       # Ruby logic patches
```

**Best for:** Mix of view, model, and controller patches

### Strategy 2: By Feature/Plugin

Group by the plugin/feature being patched:

```
app/
  views/
    helpdesk/      # All helpdesk-related patches
    agile/         # All agile-related patches
    crm/           # All CRM-related patches
```

**Best for:** Patches targeting specific plugins

### Strategy 3: By Patch Type

Group by the nature of the patch:

```
patches/
  performance/     # Performance optimizations
  bugfixes/        # Bug fixes
  features/        # New features
  compatibility/   # Compatibility patches
```

**Best for:** Clear separation of concerns

---

## Implementing Multiple Patches

### Example 1: Adding a Model Patch

**New patch:** Fix slow query in `HelpdeskTicket` model

**File:** `lib/patches/helpdesk_ticket_query_patch.rb`

```ruby
# lib/patches/helpdesk_ticket_query_patch.rb

module RedmineEeaPatches
  module Patches
    module HelpdeskTicketQueryPatch
      def self.included(base)
        base.class_eval do
          # Add a new optimized scope
          scope :for_project_fast, ->(project) {
            joins(:issue).where(issues: { project_id: project.id })
          }
          
          # Override existing slow method
          def count_for_project_slow
            # Original slow implementation
            includes(:issue => [:project]).where(projects: { id: project.id }).count
          end
          
          def count_for_project
            # Optimized implementation
            joins(:issue).where(issues: { project_id: project.id }).count
          end
        end
      end
    end
  end
end

# Apply the patch
Rails.application.config.after_initialize do
  unless HelpdeskTicket.included_modules.include?(RedmineEeaPatches::Patches::HelpdeskTicketQueryPatch)
    HelpdeskTicket.send(:include, RedmineEeaPatches::Patches::HelpdeskTicketQueryPatch)
  end
end
```

**Register in:** `lib/patches.rb`

```ruby
# lib/patches.rb
require_dependency 'patches/helpdesk_ticket_query_patch'
```

---

### Example 2: Adding Another View Patch

**New patch:** Optimize CRM contact listing

**File:** `app/views/contacts/_list.html.erb`

```erb
<%# Optimized version of redmine_crm contact list %>
<%# Original: Loads all contacts with heavy associations %>
<%# Optimized: Uses pagination and selective loading %>

<% contacts = Contact.visible.where(...).paginate(page: params[:page], per_page: 50) %>

<table class="list contacts">
  <% contacts.each do |contact| %>
    <tr>
      <td><%= contact.name %></td>
      <%# Only load what we need %>
    </tr>
  <% end %>
</table>

<%= pagination_links_full contacts %>
```

---

### Example 3: Adding a Controller Patch

**New patch:** Add caching to expensive action

**File:** `lib/patches/issues_controller_patch.rb`

```ruby
# lib/patches/issues_controller_patch.rb

module RedmineEeaPatches
  module Patches
    module IssuesControllerPatch
      def self.included(base)
        base.class_eval do
          # Cache the show action for public projects
          caches_action :show, 
                       if: -> { @project.is_public? },
                       expires_in: 1.hour,
                       cache_path: -> { "projects/#{@project.id}/issues/#{@issue.id}/#{@issue.updated_at.to_i}" }
        end
      end
    end
  end
end

Rails.application.config.after_initialize do
  IssuesController.send(:include, RedmineEeaPatches::Patches::IssuesControllerPatch)
end
```

---

## Updated init.rb for Multiple Patches

```ruby
# init.rb
require 'redmine'

Redmine::Plugin.register :redmine_eea_patches do
  name 'EEA Performance Patches'
  author 'European Environment Agency (EEA)'
  description 'Performance optimizations and compatibility patches for Redmine'
  version '1.1.0'  # Bumped for new patches
  url 'https://github.com/eea/eea.docker.redmine'
  author_url 'https://www.eea.europa.eu'
  
  requires_redmine :version_or_higher => '5.0.0'
  
  # Declare dependencies on plugins we patch
  requires_redmine_plugin :redmine_contacts_helpdesk, :version_or_higher => '4.0.0'
  requires_redmine_plugin :redmine_crm, :version_or_higher => '4.0.0'
  requires_redmine_plugin :redmine_agile, :version_or_higher => '1.6.0'
end

# Load all patches
Rails.application.config.after_initialize do
  # Load patch definitions
  require_dependency 'redmine_eea_patches/patches'
  
  Rails.logger.info '[redmine_eea_patches] Plugin loaded with patches:'
  RedmineEeaPatches::PatchRegistry.each do |patch|
    Rails.logger.info "  - #{patch.name}: #{patch.description}"
  end
end
```

---

## Patch Registry Pattern

Create a registry to track all patches:

```ruby
# lib/redmine_eea_patches/patch_registry.rb

module RedmineEeaPatches
  class PatchRegistry
    @patches = []
    
    def self.register(name, description, type: :view, options: {})
      @patches << OpenStruct.new(
        name: name,
        description: description,
        type: type,
        options: options,
        registered_at: Time.now
      )
    end
    
    def self.each(&block)
      @patches.each(&block)
    end
    
    def self.count
      @patches.size
    end
    
    def self.by_type(type)
      @patches.select { |p| p.type == type }
    end
  end
end
```

**Usage in patches:**

```ruby
# In your patch file
RedmineEeaPatches::PatchRegistry.register(
  'helpdesk_ticket_count',
  'Optimizes helpdesk ticket count query from >120s to <100ms',
  type: :view,
  options: { 
    affected_file: 'projects/_helpdesk_tickets.html.erb',
    original_plugin: 'redmine_contacts_helpdesk'
  }
)
```

---

## Testing Multiple Patches

### Test Structure

```ruby
# test/unit/patches/helpdesk_performance_test.rb

require_relative '../../test_helper'

class HelpdeskPerformancePatchTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :helpdesk_tickets
  
  def test_ticket_count_query_is_fast
    project = projects(:nanyt)
    
    time = Benchmark.measure do
      count = HelpdeskTicket.joins(:issue)
                           .where(issues: { project_id: project.id })
                           .count
    end
    
    assert time.real < 1.0, "Query took #{time.real}s, expected <1s"
  end
  
  def test_original_includes_query_is_slow
    project = projects(:nanyt)
    
    assert_timeout(5) do
      # This should timeout or be very slow
      HelpdeskTicket.includes(:issue => [:project])
                   .where(projects: { id: project.id })
                   .count
    end
  end
end
```

### Integration Tests

```ruby
# test/integration/patches_integration_test.rb

class PatchesIntegrationTest < ActionDispatch::IntegrationTest
  fixtures :users, :projects, :roles, :member_roles
  
  def test_project_page_loads_quickly_with_limited_user
    limited_user = users(:limited_user)
    project = projects(:nanyt)
    
    log_user(limited_user.login, 'password')
    
    time = Benchmark.measure do
      get project_path(project)
    end
    
    assert_response :success
    assert time.real < 5.0, "Page took #{time.real}s to load"
    
    # Verify counts are displayed
    assert_select 'span.icon-helpdesk', text: /17156/
  end
end
```

---

## Documentation Strategy

### PATCHES_INDEX.md

Maintain a catalog of all patches:

```markdown
# Patch Index

## Active Patches

### 1. Helpdesk Performance Fix
- **ID:** helpdesk_performance_001
- **File:** `app/views/projects/_helpdesk_tickets.html.erb`
- **Type:** View optimization
- **Plugin:** redmine_contacts_helpdesk
- **Issue:** Page hangs >120s for large projects
- **Solution:** Replace includes() with joins().count()
- **Status:** ✅ Active since v1.0.0
- **Test:** `test/unit/patches/helpdesk_performance_test.rb`

### 2. CRM Contact List Pagination
- **ID:** crm_pagination_001
- **File:** `app/views/contacts/_list.html.erb`
- **Type:** View optimization
- **Plugin:** redmine_crm
- **Issue:** Loads all contacts (50K+) at once
- **Solution:** Add pagination (50 per page)
- **Status:** ✅ Active since v1.1.0
- **Test:** `test/unit/patches/crm_pagination_test.rb`

### 3. Issue Controller Caching
- **ID:** issues_caching_001
- **File:** `lib/patches/issues_controller_patch.rb`
- **Type:** Controller optimization
- **Plugin:** Core Redmine
- **Issue:** Repeated expensive queries
- **Solution:** Add action caching
- **Status:** ⏸️ Disabled (causing stale data)
- **Test:** `test/unit/patches/issues_caching_test.rb`

## Deprecated Patches

None

## Future Patches

- [ ] Agile board drag-and-drop optimization
- [ ] Reporter plugin PDF generation fix
- [ ] Checklists bulk update performance
```

---

## Version Management

### Semantic Versioning for Multi-Patch Plugin

```
version '1.2.3'
│   │   │
│   │   └── Patch: Bug fix in existing patch
│   │       Example: Fixed edge case in helpdesk count
│   │
│   └─── Minor: New patch added
│         Example: Added CRM pagination patch
│
└───── Major: Breaking change
        Example: Redmine version compatibility break
```

### CHANGELOG.md

```markdown
# Changelog

## [1.1.0] - 2026-04-30

### Added
- CRM contact list pagination (crm_pagination_001)
- Issue controller action caching (issues_caching_001)
- Patch registry for tracking all patches

### Changed
- Improved test coverage for helpdesk performance patch

## [1.0.0] - 2026-04-29

### Added
- Initial release
- Helpdesk ticket count performance fix (helpdesk_performance_001)
  - Reduces query time from >120s to <100ms
  - Affects projects with >10K helpdesk tickets
```

---

## Deployment Checklist for New Patches

When adding a new patch:

- [ ] Create patch file in appropriate directory
- [ ] Register patch in `lib/patches.rb` or `lib/patches/`
- [ ] Add test in `test/unit/patches/`
- [ ] Update `PATCHES_INDEX.md`
- [ ] Update `CHANGELOG.md`
- [ ] Update `README.md` if major feature
- [ ] Bump version in `init.rb`
- [ ] Test locally
- [ ] Test in staging
- [ ] Deploy to production
- [ ] Monitor for errors
- [ ] Document any issues

---

## Common Patterns

### Pattern 1: Safe Patch Application

Always check if patch is already applied:

```ruby
unless HelpdeskTicket.included_modules.include?(MyPatch)
  HelpdeskTicket.send(:include, MyPatch)
end
```

### Pattern 2: Conditional Patches

Only apply patch if certain conditions met:

```ruby
Rails.application.config.after_initialize do
  if Redmine::Plugin.installed?(:redmine_contacts_helpdesk)
    require_dependency 'patches/helpdesk_patch'
  end
end
```

### Pattern 3: Configurable Patches

Allow patches to be disabled via settings:

```ruby
# In your patch
return if Setting.plugin_redmine_eea_patches['disable_helpdesk_patch']

# Apply patch logic
```

---

## Summary

**Key Principles:**

1. **Organize by type** (views/, models/, controllers/)
2. **Document everything** in PATCHES_INDEX.md
3. **Test each patch** individually
4. **Version properly** using semantic versioning
5. **Register patches** for visibility

**File Count Guide:**

| # of Patches | Files to Create |
|-------------|----------------|
| 1 patch | 1 view file + init.rb |
| 2-3 patches | 2-3 patch files + registry |
| 5+ patches | Full structure with tests |
| 10+ patches | Consider splitting into separate plugins |

**When to Split:**

If you have >10 patches, consider:
- `redmine_eea_performance_patches` (performance only)
- `redmine_eea_bugfix_patches` (bug fixes)
- `redmine_eea_feature_patches` (new features)

---

Ready to add your next patch? Just:

1. Create the patch file in the right directory
2. Add a test
3. Register it
4. Update documentation
5. Bump version
6. Deploy

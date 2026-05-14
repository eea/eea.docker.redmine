# Redmine Patching Strategies

## Overview

This document outlines various approaches to patching Redmine functionality, specifically for fixing the performance issue in `redmine_contacts_helpdesk`. Each approach has different trade-offs in terms of maintainability, deployment complexity, and durability.

---

## Approach 1: Runtime File Patching (Current)

**How it works:** Modify plugin files directly during container startup using shell scripts in `start_redmine.sh`.

**Implementation:**
```bash
# In start_redmine.sh
HELPDESK_PARTIAL="${REDMINE_PATH}/plugins/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb"
if [ -f "${HELPDESK_PARTIAL}" ]; then
  ruby -e '
    path = ENV["HELPDESK_PARTIAL"]
    content = File.read(path)
    # gsub replacements here
    File.write(path, patched) if patched != content
  '
fi
```

**Pros:**
- ✅ Immediate effect on pod restart
- ✅ No image rebuild required
- ✅ Simple to implement

**Cons:**
- ❌ Fragile - breaks if plugin structure changes
- ❌ Hard to maintain (string manipulation)
- ❌ No syntax validation
- ❌ Difficult to test
- ❌ Changes lost if pod dies unexpectedly

**Best for:** Emergency hotfixes, temporary workarounds

**Status:** Currently used for avatars_helper_patch.rb, but NOT for performance fix (reverted)

---

## Approach 2: Monkey Patching via Initializer

**How it works:** Create a Ruby initializer that reopens classes/modules and overrides methods at runtime using Ruby's open classes and `prepend`.

**Implementation:**
```ruby
# config/initializers/helpdesk_performance_patch.rb
module HelpdeskTicketQueryPatch
  def self.prepended(base)
    # Override specific methods
  end
  
  def count_tickets_for_project(project)
    # Optimized implementation
    joins(:issue).where(issues: { project_id: project.id }).count
  end
end

# Prepend the patch
Rails.application.config.after_initialize do
  HelpdeskTicketQuery.prepend(HelpdeskTicketQueryPatch)
end
```

**Pros:**
- ✅ Ruby-native approach
- ✅ Better testability
- ✅ Can use proper Ruby syntax/structure
- ✅ Survives pod restarts (if in persisted volume)
- ✅ Can be version controlled

**Cons:**
- ❌ Requires understanding of plugin internals
- ❌ May break with plugin updates
- ❌ Still fragile to internal API changes
- ❌ Need to identify exact method to patch

**Best for:** Method-level fixes, behavioral changes

---

## Approach 3: Custom Plugin (Recommended for Views)

**How it works:** Create a lightweight Redmine plugin that overrides specific views using Rails view lookup order.

**Implementation:**
```
plugins/zzzz_eea_patches/
├── app/
│   └── views/
│       └── projects/
│           └── _helpdesk_tickets.html.erb  # Override
├── config/
│   └── routes.rb
├── init.rb
└── lib/
    └── zzzz_eea_patches.rb
```

**init.rb:**
```ruby
Redmine::Plugin.register :zzzz_eea_patches do
  name 'EEA Patches'
  author 'EEA'
  version '1.0.0'
  requires_redmine :version_or_higher => '5.0.0'
end
```

**Pros:**
- ✅ Follows Redmine conventions
- ✅ Proper version control
- ✅ Easy to enable/disable
- ✅ Can override views, controllers, models
- ✅ Self-documenting
- ✅ Can include tests
- ✅ Can be deployed via standard plugin mechanism

**Cons:**
- ❌ Requires plugin installation process
- ❌ Another component to maintain
- ❌ Plugin loading order matters

**Best for:** Long-term patches, organizational customizations

**Implementation Steps:**
1. Create plugin directory structure
2. Copy and modify the view file
3. Add init.rb with metadata
4. Test locally
5. Add to deployment pipeline
6. Install via standard plugin mechanism

---

## Approach 4: Deface (View Overrides)

**How it works:** Use the Deface gem (commonly used in Redmine plugins) to surgically modify views without replacing entire files.

**Implementation:**
```ruby
# plugins/zzzz_eea_patches/app/overrides/helpdesk_performance_fix.rb
Deface::Override.new(
  virtual_path: 'projects/_helpdesk_tickets',
  name: 'helpdesk_performance_fix',
  replace: 'erb[silent]:contains("tickets = HelpdeskTicket")',
  text: '<% ticket_count = HelpdeskTicket.joins(:issue).where(issues: { project_id: @project.id }).count %>'
)
```

**Pros:**
- ✅ Surgical changes (don't replace entire file)
- ✅ Survives minor plugin updates
- ✅ Multiple patches can coexist
- ✅ Declarative syntax

**Cons:**
- ❌ Requires Deface gem (may not be available)
- ❌ CSS selectors can be fragile
- ❌ Adds complexity
- ❌ Debugging can be difficult

**Best for:** Small UI changes, when Deface is already in use

---

## Approach 5: Fork and Maintain Plugin

**How it works:** Fork the `redmine_contacts_helpdesk` plugin, apply fixes, and maintain your own version.

**Implementation:**
1. Fork repository from RedmineUP
2. Create branch with fixes
3. Update `addons.cfg` to use your fork
4. Rebuild image with forked plugin

**Pros:**
- ✅ Full control over plugin code
- ✅ Can optimize deeply
- ✅ Clean implementation
- ✅ Can contribute back upstream

**Cons:**
- ❌ High maintenance burden
- ❌ Must sync with upstream updates
- ❌ Security updates become your responsibility
- ❌ Requires plugin build process

**Best for:** Significant customizations, when upstream is unresponsive

---

## Approach 6: Database View Optimization

**How it works:** Create database views or materialized views to pre-compute expensive aggregations.

**Implementation:**
```sql
-- Migration
CREATE VIEW project_helpdesk_stats AS
SELECT 
  i.project_id,
  COUNT(ht.id) as ticket_count,
  COUNT(DISTINCT ht.contact_id) as customer_count
FROM helpdesk_tickets ht
JOIN issues i ON i.id = ht.issue_id
WHERE ht.contact_id IS NOT NULL
GROUP BY i.project_id;
```

```ruby
# Model
class ProjectHelpdeskStat < ApplicationRecord
  self.table_name = 'project_helpdesk_stats'
  belongs_to :project
end

# Usage in view
<% stats = ProjectHelpdeskStat.find_by(project_id: @project.id) %>
Tickets: <%= stats&.ticket_count || 0 %>
```

**Pros:**
- ✅ Database handles optimization
- ✅ Extremely fast queries
- ✅ Can use materialized views for caching
- ✅ Works with existing code structure

**Cons:**
- ❌ Database-specific (MySQL/PostgreSQL differences)
- ❌ Additional complexity
- ❌ View refresh strategy needed
- ❌ May require migrations

**Best for:** Complex aggregations, reporting queries

---

## Decision Snapshot: Option 2 vs Option 3

This section captures the previous detailed comparative analysis (now consolidated here).

### Option 2 (Initializer monkey patch)

- Strong fit for model/controller method overrides
- Weak fit for view-level ERB replacement (the current hotspot was in a view partial)
- Main risk: plugin internal API/load-order drift

### Option 3 (DB view/materialized strategy)

- Strong read performance for repeated aggregate counters
- Higher implementation/operations complexity (schema lifecycle, refresh strategy, DB portability)

### Practical conclusion for this repository

1. For immediate helpdesk sidebar remediation: use plugin/view override lane (Option 1/3 in this doc).
2. For sustained large-scale reporting counters: DB-view lane can be evaluated as a second phase.
3. For upstream compatibility: prefer minimal SQL aggregate changes in plugin code over local heavy metaprogramming.

---

## Approach 7: Rails Fragment Caching

**How it works:** Cache the expensive partial rendering using Rails cache.

**Implementation:**
```erb
<% cache(['helpdesk_sidebar', @project.id, @project.updated_at.to_i]) do %>
  <% ticket_count = HelpdeskTicket.joins(:issue)... %>
  <% customer_count = HelpdeskTicket.joins(:issue)... %>
  <%= sprite_icon(...) %>
<% end %>
```

**Pros:**
- ✅ Simple to implement
- ✅ Survives with original slow query
- ✅ Configurable cache backend (Redis/Memcached)
- ✅ Automatic invalidation via cache key

**Cons:**
- ❌ First request still slow
- ❌ Cache invalidation complexity
- ❌ Memory overhead
- ❌ Stale data concerns

**Best for:** When you can't change the query, need quick win

---

## Approach 8: Upstream Contribution

**How it works:** Submit fix to RedmineUP for inclusion in official plugin releases.

**Implementation:**
1. Create minimal reproduction case
2. Fork their repository
3. Apply fix with tests
4. Submit pull request or support ticket
5. Wait for release
6. Update to new version

**Pros:**
- ✅ No maintenance burden
- ✅ Benefits community
- ✅ Proper code review
- ✅ Sustainable long-term

**Cons:**
- ❌ Timeline uncertain
- ❌ May be rejected
- ❌ Commercial plugin (may not accept contributions)
- ❌ No immediate relief

**Best for:** Long-term, when fix benefits broader community

---

## Recommendation Matrix

| Scenario | Recommended Approach | Why |
|----------|---------------------|-----|
| **Emergency hotfix** | Approach 1 (Runtime patch) | Fastest to deploy |
| **Long-term fix** | Approach 3 (Custom plugin) | Maintainable, version controlled |
| **Small UI change** | Approach 4 (Deface) | Surgical, clean |
| **Heavy customization** | Approach 5 (Fork) | Full control |
| **Reporting/aggregations** | Approach 6 (DB views) | Maximum performance |
| **Can't change query** | Approach 7 (Caching) | Work with constraints |
| **Fix upstream** | Approach 8 (Contribution) | Sustainable |
| **Method-level fix** | Approach 2 (Monkey patch) | Ruby-native |

---

## Recommended Implementation for This Issue

Given the specific problem (slow query in plugin view), here are the top 3 approaches ranked by preference:

### Option 1: Custom Plugin (BEST)

Create `plugins/redmine_eea_performance_patches/`:

```
plugins/redmine_eea_performance_patches/
├── app/
│   └── views/
│       └── projects/
│           └── _helpdesk_tickets.html.erb
├── init.rb
└── README.md
```

**Why:** Clean, version controlled, follows conventions, easy to deploy

**Deployment:** Add to Docker image build or mount via ConfigMap

### Option 2: Initializer Patch

Create `config/initializers/helpdesk_performance_patch.rb`:

```ruby
# Override the view rendering at the controller level
# or patch the query method if accessible
```

**Why:** No new plugin structure, Ruby-native

**Deployment:** Mount via ConfigMap or include in image

### Option 3: Database View + Custom Plugin

Combine database view for performance with custom plugin for clean code.

**Why:** Maximum performance, clean implementation

**Deployment:** Migration + plugin

---

## Implementation Checklist

Regardless of approach chosen:

- [ ] Identify exact code to patch
- [ ] Write test case
- [ ] Implement patch
- [ ] Test locally
- [ ] Document the patch
- [ ] Add to version control
- [ ] Update deployment pipeline
- [ ] Monitor after deployment
- [ ] Plan for upstream updates

---

## Next Steps

1. **Choose approach** based on timeline and maintenance capacity
2. **Create proof-of-concept** with chosen approach
3. **Test thoroughly** in staging environment
4. **Document the solution** for team knowledge
5. **Consider upstream contribution** for long-term sustainability

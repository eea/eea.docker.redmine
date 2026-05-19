# Current Patches (Single Source of Truth)

This is the **only authoritative patch catalog**.

Format used for every patch:
- File
- Problem
- Solution
- Code (`Before` / `After`)
- Performance
- Affected Projects

---

## Current Patches

### 1. Helpdesk Ticket Count Performance Fix

**File:** `plugins/zzzz_eea_patches/app/views/projects/_helpdesk_tickets.html.erb`

**Problem:** The `redmine_contacts_helpdesk` plugin loaded very large relations before counting, causing page hangs on big private projects.

**Solution:** Replace eager-loading count path with indexed SQL aggregate counts.

```ruby
# Before
tickets = HelpdeskTicket.includes(issue: [:project]).where(projects: { id: @project })
tickets.count

# After
ticket_count = HelpdeskTicket.joins(:issue).where(issues: { project_id: @project.id }).count
customer_count = HelpdeskTicket.joins(:issue).where(issues: { project_id: @project.id }).where.not(contact_id: nil).distinct.count(:contact_id)
```

**Performance:**
- Query time: >120s → <100ms (>99.9% improvement)
- Data transfer: ~1M+ values → 2 integers

**Affected Projects:**
- nanyt (EEA enquiries)

---

### 2. AGILE_QUERY
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_AGILE_QUERY`)

**Problem:** Board status lookup used heavier tracker/workflow path.

**Solution:** Fetch tracker IDs first, then query workflow transitions directly.

```ruby
# Before
statuses = expensive_workflow_lookup(issue_scope)

# After
tracker_ids = issue_scope.where.not(tracker_id: nil).distinct.pluck(:tracker_id)
status_ids = WorkflowTransition.where(tracker_id: tracker_ids).pluck(:old_status_id, :new_status_id).flatten.uniq
IssueStatus.where(id: status_ids)
```

**Performance:** ~4.8x speedup (benchmark snapshot)

**Affected Projects:** Agile board-heavy projects

### 3. AGILE_ISSUES_IDS
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_AGILE_ISSUES_IDS`)

**Problem:** `map(&:id)` instantiated many objects just to get IDs.

**Solution:** Use `pluck(:id)`.

```ruby
# Before
ids = issue_scope.map(&:id)

# After
ids = issue_scope.pluck(:id)
```

**Performance:** ~17.4x speedup

**Affected Projects:** Large agile issue scopes

### 4. RESOURCE_BOOKING_QUERY
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_RESOURCE_BOOKING_QUERY`)

**Problem:** Booking issue IDs collected with Ruby iteration.

**Solution:** Direct `pluck(:issue_id)`.

```ruby
# Before
ids = approved_bookings.map(&:issue_id)

# After
ids = approved_bookings.pluck(:issue_id)
```

**Performance:** ~25.1x speedup

**Affected Projects:** Resource booking flows

### 5. AGILE_DOUBLE_COUNT
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_AGILE_DOUBLE_COUNT`)

**Problem:** Separate COUNT + SELECT added extra DB round-trip.

**Solution:** `limit + 1` fetch in one query.

```ruby
# Before
count = scope.count
rows = scope.limit(limit).to_a

# After
rows = scope.limit(limit + 1).to_a
rows = rows.first(limit) if rows.size > limit
```

**Performance:** ~16.8x speedup

**Affected Projects:** Agile board pagination

### 6. AGILE_DESCENDANTS_JOIN
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_AGILE_DESCENDANTS_JOIN`)

**Problem:** Descendant filtering done in Ruby (`select/map`).

**Solution:** SQL join on `enabled_modules` + `pluck(:id)`.

```ruby
# Before
ids = project.descendants.select { |p| p.module_enabled?('agile') }.map(&:id)

# After
ids = project.descendants.joins(:enabled_modules).where(enabled_modules: { name: 'agile' }).pluck(:id)
```

**Performance:** ~2.6x speedup in deep trees

**Affected Projects:** Multi-level project hierarchies

### 7. AGILE_SPRINT_PROJECTS
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_AGILE_SPRINT_PROJECTS`)

**Problem:** Nested Ruby map/flatten/uniq for shared sprint projects.

**Solution:** SQL join + `pluck`.

```ruby
# Before
ids = project.shared_agile_sprints.map(&:shared_projects).map { |ps| ps.map(&:id) }.flatten.uniq

# After
ids = AgileSprint.joins(:shared_projects).where(agile_sprints: { id: project.shared_agile_sprints.pluck(:id) }).pluck('projects.id').uniq
```

**Performance:** ~15.6x speedup

**Affected Projects:** Sprint-sharing setups

### 8. HELPDESK_COLLECTOR
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_HELPDESK_COLLECTOR`)

**Problem:** Customer IDs in collector path mapped via Ruby.

**Solution:** Join + direct `pluck`.

```ruby
# Before
ids = issues_scope.joins(:customer).map(&:customer).map(&:id)

# After
ids = issues_scope.joins(:customer).pluck("#{Contact.table_name}.id")
```

**Performance:** improved in profiling (plugin-load dependent in some test lanes)

**Affected Projects:** Helpdesk collector/analytics flows

### 9. AGILE_SPRINT_HOURS_SUM
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_AGILE_SPRINT_HOURS_SUM`)

**Problem:** Sprint totals used less efficient paths.

**Solution:** DB aggregate sums after controller `super`.

```ruby
# Before
@estimated_hours = @issues.map(&:estimated_hours).compact.sum

# After
@estimated_hours = @issues.sum(:estimated_hours)
```

**Performance:** reduced aggregation overhead (no standalone micro-benchmark)

**Affected Projects:** Agile sprint dashboards

### 10. CONTACTS_IDS
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_CONTACTS_IDS`)

**Problem:** Contacts index lane needed compatibility-safe wrapper and fallback.

**Solution:** Controller prepend with guarded fallback.

```ruby
# Before
contacts_ids = contacts.map(&:id)

# After
contacts_ids = contacts.pluck(:id) # when applicable in query paths
```

**Performance:** compatibility-focused

**Affected Projects:** CRM contacts pages

### 11. HELPDESK_PROJECT_CHILDREN
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_HELPDESK_PROJECT_CHILDREN`)

**Problem:** Child project filtering done with Ruby select/map.

**Solution:** SQL join + `pluck(:id)`.

```ruby
# Before
ids = [project.id] + project.children.select { |c| c.module_enabled?(:contacts_helpdesk) }.map(&:id)

# After
ids = [project.id] + project.children.joins(:enabled_modules).where(enabled_modules: { name: :contacts_helpdesk }).pluck(:id)
```

**Performance:** reduced iteration/query overhead

**Affected Projects:** Helpdesk in project trees

### 12. RESOURCE_BOOKING_BLANK_ISSUE
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_RESOURCE_BOOKING_BLANK_ISSUE`)

**Problem:** Blank-issue checks iterated Ruby objects.

**Solution:** SQL null filter + `pluck`.

```ruby
# Before
ids = resource_bookings.select { |rb| rb.issue.blank? }.map(&:project_id)

# After
ids = resource_bookings.where(issue_id: nil).pluck(:project_id)
```

**Performance:** reduced object materialization

**Affected Projects:** Resource planning boards

### 13. DEAL_LINES_SUM
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_DEAL_LINES_SUM`)

**Problem:** Deal totals computed with Ruby loops.

**Solution:** Use DB aggregate sums.

```ruby
# Before
tax = lines.select { |l| !l.marked_for_destruction? }.inject(0) { |sum, l| sum + l.tax_amount }

# After
tax = lines.where(marked_for_destruction: false).sum(:tax_amount)
```

**Performance:** reduced CPU/iteration

**Affected Projects:** CRM deals

### 14. CONTACT_NOTES_ATTACHMENTS
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_CONTACT_NOTES_ATTACHMENTS`)

**Problem:** Note IDs built with Ruby `map`.

**Solution:** Use `pluck(:id)`.

```ruby
# Before
Attachment.where(container_type: 'Note', container_id: notes.map(&:id))

# After
Attachment.where(container_type: 'Note', container_id: notes.pluck(:id))
```

**Performance:** ~7.3x speedup

**Affected Projects:** Contact notes history

### 15. CONTACTS_CONTROLLER_CAN
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_CONTACTS_CONTROLLER_CAN`)

**Problem:** Bulk permission flags could drift and repeat checks.

**Solution:** Normalize in one bulk pass.

```ruby
# Before
@can[:edit] = @contacts.collect { |c| c.editable? }.inject { |a, b| a && b }

# After
@can[:edit] = @contacts.all?(&:editable?)
```

**Performance:** consistency-focused

**Affected Projects:** Contacts bulk action screens

### 16. CONTACT_GROUPS_IDS
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_CONTACT_GROUPS_IDS`)

**Problem:** Visibility path used heavier traversal.

**Solution:** Narrow projects through SQL join/subquery lane first.

```ruby
# Before
projects.any? { |project| usr.allowed_to?(:view_contacts, project) }

# After
projects_with_contacts = Project.joins(:enabled_modules).where(enabled_modules: { name: 'contacts' }).where(id: ContactsProject.where(contact_id: id).select(:project_id))
projects_with_contacts.any? { |project| usr.allowed_to?(:view_contacts, project) }
```

**Performance:** reduced query/iteration overhead

**Affected Projects:** Private contacts visibility checks

### 17. AGILE_VERSIONS_QUERY
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_AGILE_VERSIONS_QUERY`)

**Problem:** Tracker IDs collected with Ruby mapping.

**Solution:** `pluck(:id)`.

```ruby
# Before
ids = project.trackers.where(is_in_roadmap: true).map(&:id)

# After
ids = project.trackers.where(is_in_roadmap: true).pluck(:id)
```

**Performance:** ~9.4x speedup

**Affected Projects:** Agile roadmap views

### 18. AGILE_SPRINTS_QUERY
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_AGILE_SPRINTS_QUERY`)

**Problem:** Descendant IDs collected with Ruby mapping.

**Solution:** `pluck(:id)` with guards.

```ruby
# Before
ids += project.descendants.map(&:id)

# After
ids += project.descendants.pluck(:id)
```

**Performance:** ~15.3x speedup

**Affected Projects:** Sprint query flows

### 19. TIME_ENTRY_CUSTOM_VALUES
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_TIME_ENTRY_CUSTOM_VALUES`)

**Problem:** Time entries triggered N+1 for custom values.

**Solution:** Preload `custom_values` and `custom_field`.

```ruby
# Before
scope = super

# After
scope = super.preload(custom_values: :custom_field)
```

**Performance:** ~25 queries → 1 (lane-specific)

**Affected Projects:** Time entries pages/reports

### 20. TIME_ENTRY_PROJECT_MODULES
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_TIME_ENTRY_PROJECT_MODULES`)

**Problem:** `module_enabled?` checked per project and could query repeatedly.

**Solution:** Batch load `enabled_modules` and inject per-project cache.

```ruby
# Before
time_entries.each { |te| te.project.module_enabled?(:timelog) }

# After
modules_map = EnabledModule.where(project_id: project_ids).group_by(&:project_id)
time_entries.each { |te| te.project.instance_variable_set(:@enabled_modules, modules_map[te.project.id] || []) }
```

**Performance:** ~11 queries → 1 (lane-specific)

**Affected Projects:** Multi-project time entry lists

### 21. TIME_ENTRY_SUM_HOURS
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_TIME_ENTRY_SUM_HOURS`)

**Problem:** Sum query could run redundantly.

**Solution:** Cache computed sum from base scope.

```ruby
# Before
scope.sum(:hours) # repeated

# After
@cached_hours_sum ||= scope.sum(:hours)
```

**Performance:** removes duplicate sum query

**Affected Projects:** Time log summaries

### 22. PROJECT_MEMBERS_PRELOAD
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_PROJECT_MEMBERS_PRELOAD`)

**Problem:** `principals_by_role` had N+1 across memberships/roles/principals.

**Solution:** `includes(:principal, member_roles: :role)` and iterate preloaded associations.

```ruby
# Before
members.each { |m| m.roles.each { |r| ... } }

# After
memberships.active.includes(:principal, member_roles: :role).each { |m| m.member_roles.each { |mr| r = mr.role; ... } }
```

**Performance:** significant reduction in role/member query chatter

**Affected Projects:** Member/role rendering paths

### 23. PROJECT_MEMBERS_COUNT
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_PROJECT_MEMBERS_COUNT`)

**Problem:** Role counts required repeated joins/count scans.

**Solution:** Use cache where present; fallback to SQL count.

```ruby
# Before
members.joins(:member_roles).where(member_roles: { role_id: role_id }).count

# After
member_roles_count_cache[role_id] || members.joins(:member_roles).where(member_roles: { role_id: role_id }).count
```

**Performance:** faster with cache; safe fallback

**Affected Projects:** Membership statistics

### 24. USER_ROLES_PRELOAD
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_USER_ROLES_PRELOAD`)

**Problem:** `User#roles` repeatedly executed heavy joins; stale-cache risk in permission paths.

**Solution:** Fresh-data-safe scoped role query implementation.

```ruby
# Before
Role.joins(members: :project).where(...).where(members: { user_id: id }).distinct.to_a

# After
# same logical query wrapped in patch lane with resilient fallback and anon/non-member handling
```

**Performance:** reduced repeated role-query overhead while preserving permission correctness

**Affected Projects:** Permission-sensitive issue/board flows

### 26. BANNER_ENGINE_ROUTES
**File:** `plugins/zzzz_eea_patches/app/views/banner/_body_bottom.html.erb`
**File:** `plugins/zzzz_eea_patches/app/views/banner/_project_body_bottom.html.erb`

**Problem:** When `redmine_banner` partials are rendered inside another engine's scope (e.g. `ai_helper`), `link_to` and `url_for` resolve controller paths relative to the engine's routes. This produces routes like `ai_helper/global_banner/zope` which don't exist, causing `ActionController::UrlGenerationError: No route matches`.

**Solution:** Override both banner partials and prefix all `controller:` references with `main_app/` to force resolution against the main application's routes.

```erb
# Before (original redmine_banner partial)
<%= link_to l(:button_edit),
  { controller: 'global_banner', action: 'show' },
  { class: 'icon banner-icon-edit', title: l(:button_edit)} if User.current.admin? %>

# After (EEA patch override)
<%= link_to l(:button_edit),
  { controller: 'main_app/global_banner', action: 'show' },
  { class: 'icon banner-icon-edit', title: l(:button_edit)} if User.current.admin? %>
```

Same fix applied to:
- `controller: 'banner'` → `controller: 'main_app/banner'` (global banner off toggle)
- `controller: 'banner'` → `controller: 'main_app/banner'` (project banner show)
- `url_for(controller: :banner, ...)` → `url_for(controller: 'main_app/banner', ...)` (project banner off AJAX)

**Performance:** No performance impact — purely a routing correctness fix.

**Affected Engines/Plugins:**
- redmine_ai_helper (triggering `AiHelper::CustomCommandsController#new`)
- Any other Redmine engine that triggers `view_layouts_base_body_bottom` hooks

---

### 25. ACTIVITY_AUTHOR_PRELOAD
**File:** `config/initializers/runtime_compat.rb` (`TASKMAN_PATCH_ACTIVITY_AUTHOR_PRELOAD`)

**Problem:** Activity rendering repeatedly resolved `event_author` on large event sets.

**Solution:** Bulk preload `:author` in `Redmine::Activity::Fetcher#events` (HTML lane, guarded).

```ruby
# Before
events.each { |e| e.event_author }

# After
events.group_by(&:class).each do |_klass, class_events|
  ActiveRecord::Associations::Preloader.new(records: class_events, associations: :author).call
end
```

**Performance:**
- latency improved from ~30s timeout-prone behavior to ~12s in tested env
- query count still high on very large windows; pagination/cap still recommended

**Affected Projects:** High-volume `/projects/:identifier/activity`

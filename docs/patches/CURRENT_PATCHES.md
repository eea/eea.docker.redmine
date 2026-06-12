# Current Patches

All runtime patches are in `config/initializers/runtime_compat.rb`, deployed via ConfigMap `taskman-runtime-compat`. Toggle each with `TASKMAN_PATCH_<NAME>=1|0` as a deployment env var. No image rebuild required.

For the patch inventory/status table see `docs/patches/PATCHES.md`.

---

## Member Roles Patches

These three patches work together to fix slow load times on projects with deep inheritance hierarchies where `member_roles` has many inherited rows.

### PROJECT_MEMBERS_PRELOAD
**Toggle:** `TASKMAN_PATCH_PROJECT_MEMBERS_PRELOAD=1`
**Target:** `Project#principals_by_role` — called from `ProjectsController#show`

**Problem:** The original implementation used `includes(member_roles: :role)` which loaded all inherited member_roles rows for the project via an IN-clause query into Ruby memory.

**Solution:** Load members with principals once, then use a single `DISTINCT` query on the `(member_id, role_id)` composite index — a covering index scan that returns only distinct role assignments.

```ruby
# Before
scope = memberships.active.includes(:principal, member_roles: :role)
scope.each { |m| m.roles.each { |r| result[r] << m.principal } }

# After
pairs = MemberRole.where(member_id: member_ids).distinct.pluck(:member_id, :role_id)
roles_by_id = Role.where(id: pairs.map(&:last).uniq).index_by(&:id)
# build {role => [principals]} from hash lookups — zero N+1
```

**Performance:** Significant improvement on affected projects

---

### SORTED_SCOPE
**Toggle:** `TASKMAN_PATCH_SORTED_SCOPE=1`
**Target:** `Member.sorted` class method via `Member.singleton_class.prepend`

**Problem:** `Member.sorted` uses `includes(:member_roles, :roles, :principal)`. Because `:roles` is `has_many :through :member_roles`, this JOINs all inherited member_roles rows — the result set can be tens of megabytes.

**Solution:** Correlated scalar subquery for MIN(role.position) per member, plus `preload(:principal)` for the principal association. Only activates when `taskman_member_roles_bulk_map` is set (i.e. inside the settings action) — falls back to the original scope everywhere else.

```ruby
# Before
scope :sorted, -> {
  includes(:member_roles, :roles, :principal)
    .reorder("#{Role.table_name}.position")
    .order(Principal.fields_for_order_statement)
}

# After (settings action only, guarded by thread-local)
joins(:principal)
  .select("members.*, (SELECT COALESCE(MIN(r.position), 999)
     FROM member_roles mr INNER JOIN roles r ON r.id = mr.role_id
     WHERE mr.member_id = members.id) AS taskman_min_role_pos")
  .reorder("taskman_min_role_pos")
  .order(Principal.fields_for_order_statement)
  .preload(:principal)
```

**Performance:** Settings/members page: eliminates the JOIN explosion

---

### MEMBER_ROLES_SETTINGS_BULK_PRELOAD
**Toggle:** `TASKMAN_PATCH_MEMBER_ROLES_SETTINGS_BULK_PRELOAD` (default: on)
**Target:** `ProjectsController#settings` + `Member#roles` + `Member#any_inherited_role?`

**Problem:** After `sorted.to_a` loads members, the view calls `member.roles` and `member.deletable?` per member in the loop — each firing SQL queries.

**Solution:** Patch `ProjectsController#settings` to run before `super`. Two DISTINCT queries (kept separate to preserve covering index usage) pre-load all needed data into thread-locals before the view renders. The view loop fires zero SQL.

```ruby
# Before (per member in view loop)
member.roles        # SELECT DISTINCT roles.* ... WHERE member_id=X
member.deletable?   # → any_inherited_role? → SELECT 1 FROM member_roles WHERE member_id=X LIMIT 1

# After (once, before view renders)
pairs = MemberRole.where(member_id: member_ids).distinct.pluck(:member_id, :role_id)
# → Thread.current[:taskman_member_roles_bulk_map] = { member_id => [roles] }
inherited_ids = MemberRole.where(member_id: member_ids).where.not(inherited_from: nil).distinct.pluck(:member_id)
# → Thread.current[:taskman_inherited_member_ids] = Set<member_id>

# In view loop: O(1) hash/Set lookups, zero SQL
```

**Why two queries instead of one GROUP BY:** Adding `MAX(inherited_from IS NOT NULL)` to the GROUP BY forces MySQL off the `(member_id, role_id)` covering index because `inherited_from` is not in that index. Two separate DISTINCT queries each use their own covering index.

**Performance:** Significant improvement on affected projects

---

## Plugin Performance Patches

### AGILE_QUERY
**Toggle:** `TASKMAN_PATCH_AGILE_QUERY=1`
**Target:** `AgileQuery#board_issue_statuses`

**Problem:** Board status lookup joined through tracker/project to workflows.

**Solution:** Fetch tracker IDs first, then query workflow transitions directly.

```ruby
# Before
statuses = expensive_workflow_join(issue_scope)

# After
tracker_ids = issue_scope.unscope(:select, :order).where.not(tracker_id: nil).distinct.pluck(:tracker_id)
status_ids = WorkflowTransition.where(tracker_id: tracker_ids).distinct.pluck(:old_status_id, :new_status_id).flatten.uniq
IssueStatus.where(id: status_ids)
```

---

### AGILE_ISSUES_IDS
**Toggle:** `TASKMAN_PATCH_AGILE_ISSUES_IDS=1`
**Target:** `AgileQuery#issues_ids`

```ruby
# Before
ids = issue_scope.map(&:id)
# After
ids = issue_scope.unscope(:select, :order).pluck(:id)
```

---

### RESOURCE_BOOKING_QUERY
**Toggle:** `TASKMAN_PATCH_RESOURCE_BOOKING_QUERY=1`
**Target:** `ResourceBookingQuery#booked_issue_ids`

```ruby
# Before
ids = approved_bookings.map(&:issue_id)
# After
ids = approved_bookings.pluck(:issue_id)
```

---

### AGILE_DOUBLE_COUNT
**Toggle:** `TASKMAN_PATCH_AGILE_DOUBLE_COUNT=1`
**Target:** `AgileQuery#issue_board`

**Problem:** Separate COUNT query before data fetch.

**Solution:** Fetch limit+1 rows and trim in Ruby. Only applies when `limit` is provided.

```ruby
# Before
count = scope.count; rows = scope.limit(limit).to_a
# After
rows = scope.limit(limit + 1).to_a; rows = rows.first(limit) if rows.size > limit
```

---

### AGILE_DESCENDANTS_JOIN
**Toggle:** `TASKMAN_PATCH_AGILE_DESCENDANTS_JOIN=1`
**Target:** `AgileQuery#agile_subproject_ids`

```ruby
# Before
project.descendants.select { |p| p.module_enabled?('agile') }.map(&:id)
# After
project.descendants.joins(:enabled_modules).where(enabled_modules: { name: 'agile' }).pluck(:id)
```

---

### AGILE_SPRINT_PROJECTS
**Toggle:** `TASKMAN_PATCH_AGILE_SPRINT_PROJECTS=1`
**Target:** `AgileQuery#shared_sprint_project_ids`

```ruby
# Before
project.shared_agile_sprints.map(&:shared_projects).map { |ps| ps.map(&:id) }.flatten.uniq
# After
AgileSprint.joins(:shared_projects).where(agile_sprints: { id: project.shared_agile_sprints.pluck(:id) }).pluck('projects.id').uniq
```

---

### HELPDESK_COLLECTOR
**Toggle:** `TASKMAN_PATCH_HELPDESK_COLLECTOR=1`
**Target:** `HelpdeskDataCollectorBusiestTime#customer_ids_for_issues`

```ruby
# Before
issues_scope.joins(:customer).map(&:customer).map(&:id)
# After
issues_scope.joins(:customer).pluck("#{Contact.table_name}.id")
```

---

### AGILE_SPRINT_HOURS_SUM
**Toggle:** `TASKMAN_PATCH_AGILE_SPRINT_HOURS_SUM=1`
**Target:** `AgileSprintsController#show`

**Solution:** DB aggregate sums after `super`.

```ruby
@estimated_hours = @issues.sum(:estimated_hours)
@spent_hours = @issues.joins(:time_entries).sum('time_entries.hours')
@story_points = @issues.joins(:agile_data).sum('agile_data.story_points')
```

---

### HELPDESK_PROJECT_CHILDREN
**Toggle:** `TASKMAN_PATCH_HELPDESK_PROJECT_CHILDREN=1`
**Target:** `HelpdeskTicket#project_ids_with_children`

```ruby
# Before
[project.id] + project.children.select { |c| c.module_enabled?(:contacts_helpdesk) }.map(&:id)
# After
[project.id] + project.children.joins(:enabled_modules).where(enabled_modules: { name: :contacts_helpdesk }).pluck(:id)
```

---

### RESOURCE_BOOKING_BLANK_ISSUE
**Toggle:** `TASKMAN_PATCH_RESOURCE_BOOKING_BLANK_ISSUE=1`
**Target:** `WeekPlan`, `MonthPlan`, `Plan`

```ruby
# Before
resource_bookings.select { |rb| rb.issue.blank? }.map(&:project_id)
# After
resource_bookings.where(issue_id: nil).pluck(:project_id)
```

---

### DEAL_LINES_SUM
**Toggle:** `TASKMAN_PATCH_DEAL_LINES_SUM=1`
**Target:** `Deal#tax_amount`, `#total_amount`, `#total_quantity`

**Problem:** Original code used Ruby loops over loaded objects. A previous patch attempt used `where(marked_for_destruction: false)` — `marked_for_destruction` is not a DB column and would raise `StatementInvalid`. Fixed to use SQL SUM directly.

```ruby
# Before
lines.select { |l| !l.marked_for_destruction? }.inject(0) { |sum, l| sum + l.tax_amount }
# After
lines.sum(:tax_amount)
```

---

### CONTACT_NOTES_ATTACHMENTS
**Toggle:** `TASKMAN_PATCH_CONTACT_NOTES_ATTACHMENTS=1`
**Target:** `Contact#contact_attachments`

```ruby
# Before
Attachment.where(container_type: 'Note', container_id: notes.map(&:id))
# After
Attachment.where(container_type: 'Note', container_id: notes.pluck(:id))
```

---

### CONTACT_GROUPS_IDS
**Toggle:** `TASKMAN_PATCH_CONTACT_GROUPS_IDS=1`
**Target:** `Contact#visible?`

**Solution:** Narrow project set through SQL JOIN/subquery before checking permissions.

```ruby
projects_with_contacts = Project.joins(:enabled_modules)
  .where(enabled_modules: { name: 'contacts' })
  .where(id: ContactsProject.where(contact_id: id).select(:project_id))
projects_with_contacts.any? { |project| usr.allowed_to?(:view_contacts, project) }
```

---

### AGILE_VERSIONS_QUERY
**Toggle:** `TASKMAN_PATCH_AGILE_VERSIONS_QUERY=1`
**Target:** `AgileVersionsQuery#roadmap_tracker_ids`

```ruby
# Before
project.trackers.where(is_in_roadmap: true).map(&:id)
# After
project.trackers.where(is_in_roadmap: true).pluck(:id)
```

---

### AGILE_SPRINTS_QUERY
**Toggle:** `TASKMAN_PATCH_AGILE_SPRINTS_QUERY=1`
**Target:** `AgileSprintsQuery#project_ids_with_descendants`

```ruby
# Before
ids += project.descendants.map(&:id)
# After
ids += project.descendants.pluck(:id)
```

---

### TIME_ENTRY_CUSTOM_VALUES
**Toggle:** `TASKMAN_PATCH_TIME_ENTRY_CUSTOM_VALUES=1`
**Target:** `TimeEntryQuery#results_scope`

**Problem:** N+1 loading custom values per time entry.

```ruby
# After
scope.preload(custom_values: :custom_field)
```

---

### TIME_ENTRY_PROJECT_MODULES
**Toggle:** `TASKMAN_PATCH_TIME_ENTRY_PROJECT_MODULES=1`
**Target:** `TimelogController#index`

**Problem:** `project.module_enabled?` queried per project.

**Solution:** Batch preload `enabled_modules` and inject into project instances.

```ruby
modules_map = EnabledModule.where(project_id: project_ids).group_by(&:project_id)
time_entries.each { |te| te.project.instance_variable_set(:@enabled_modules, modules_map[te.project.id] || []) }
```

---

### TIME_ENTRY_SUM_HOURS
**Toggle:** `TASKMAN_PATCH_TIME_ENTRY_SUM_HOURS=1`
**Target:** `TimeEntryQuery#default_total_hours`

**Problem:** Sum query could run redundantly. `responseable?` and `base_scope` may not exist on all instances — guarded with `respond_to?`.

```ruby
return total if total.present? || !respond_to?(:responseable?) || !responseable?
scope = respond_to?(:base_scope) ? base_scope : nil
@cached_hours_sum ||= scope.sum(:hours)
```

---

### ACTIVITY_AUTHOR_PRELOAD
**Toggle:** `TASKMAN_PATCH_ACTIVITY_AUTHOR_PRELOAD` (default: on)
**Target:** `Redmine::Activity::Fetcher#events`

**Problem:** Activity rendering hit N+1 resolving `event_author` on large event sets.

**Solution:** Bulk preload `:author` after events are grouped by class. HTML lane only (Atom already paginates).

```ruby
events.group_by(&:class).each do |klass, class_events|
  next unless klass.reflect_on_association(:author)
  ActiveRecord::Associations::Preloader.new(records: class_events, associations: :author).call
end
```

---

## Disabled Patches

### USER_ROLES_PRELOAD
**Toggle:** `TASKMAN_PATCH_USER_ROLES_PRELOAD=0`
**Risk:** Full reimplementation of `User#roles` — a security-critical method that controls permissions across the entire app. Any subtle difference from the original (missing a project status check, wrong scope) could silently grant or deny access. Enable only after thorough testing.

---

### CONTACTS_CONTROLLER_CAN
**Toggle:** `TASKMAN_PATCH_CONTACTS_CONTROLLER_CAN=0`
**Risk:** Overwrites `@can[:edit]`, `@can[:delete]`, `@can[:send_mails]` set by `super`. If `super` applies additional permission restrictions, this patch silently discards them.

---

### WIKI_LINKS_MAIN_APP
**Toggle:** `TASKMAN_PATCH_WIKI_LINKS_MAIN_APP=0`
**Risk:** Full reimplementation of `ApplicationHelper#parse_wiki_links`. Any upstream change to this method in Redmine won't be reflected here. Re-enable only if the AI helper engine wiki routing bug recurs.

---

## Plugin View Fixes (not runtime_compat)

### Helpdesk Sidebar Count
**Location:** `plugins/zzzz_eea_patches/` view override of `projects/_helpdesk_tickets.html.erb`

**Problem:** `HelpdeskTicket.includes(:issue => [:project]).where(...).count` loaded all helpdesk tickets with full JOINs before calling `.count` — timeout on large private projects.

**Solution:** `JOIN + COUNT(*)` — returns 1 integer.

```ruby
# Before
tickets = HelpdeskTicket.includes(issue: [:project]).where(projects: { id: @project })
tickets.count   # loads all records into memory first

# After
ticket_count = HelpdeskTicket.joins(:issue).where(issues: { project_id: @project.id }).count
customer_count = HelpdeskTicket.joins(:issue).where(issues: { project_id: @project.id }).where.not(contact_id: nil).distinct.count(:contact_id)
```

**Performance:** Timeout eliminated

---

### Banner Engine Routes
**Location:** `plugins/zzzz_eea_patches/` view overrides of banner partials

**Problem:** When `redmine_banner` partials render inside another engine's scope (e.g. `ai_helper`), `link_to` resolves routes relative to the engine, producing URLs like `ai_helper/global_banner/zope` which don't exist.

**Solution:** Route banner actions through `main_app` to force resolution against the main application's routes.

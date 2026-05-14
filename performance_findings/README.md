# Taskman Performance Findings: Helpdesk Investigation

**Date:** 2026-04-29  
**Environment:** 02pre/taskman  
**Affected Component:** redmine_contacts_helpdesk plugin

---

## Executive Summary

The `/projects/nanyt` page hangs indefinitely (>120s timeout) for users with limited permissions when accessing the EEA enquiries project. This is caused by the `redmine_contacts_helpdesk` plugin's project overview sidebar performing expensive LEFT JOIN queries that load 17,156 records with 61 columns each.

### Quick Navigation

- `README.md` (this file): root-cause narrative and recommended fix
- `FIX_IMPLEMENTATION.md`: exact code-level implementation steps
- `TESTING_GUIDE.md`: test and benchmark procedure
- `PATCH_OPERATIONS.md`: rollout/rollback operations checklist
- `PATCHING_STRATEGIES.md`: strategy comparison and long-term options
- `OPTION_1_DEEP_DIVE.md`: detailed plugin override lane
- `sql_analysis.sql`: raw SQL comparisons
- `benchmark.rb`: benchmark helper script

---

## Problem Details

### Affected Project
| Attribute | Value |
|-----------|-------|
| **Identifier** | nanyt |
| **Name** | EEA enquiries |
| **ID** | 161 |
| **Visibility** | Private (is_public: false) |
| **Total Issues** | 17,159 |
| **Helpdesk Tickets** | 17,156 |
| **Distinct Customers** | 11,244 |

### Symptom
Users with limited permissions (e.g., bulanmir, user ID 17) experience indefinite page hangs when accessing `/projects/nanyt`. The request eventually times out.

---

## Root Cause Analysis

### Slow Code Location
**File:** `plugins/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb`

```erb
<% if tickets = HelpdeskTicket.includes(:issue => [:project]).where(:projects => {:id => @project}) %>
  <% customers = Contact.includes(:tickets => :project).where(:projects => {:id => @project}) %>
  <%= sprite_icon('icon-helpdesk', l(:text_helpdesk_ticket_count, :count => tickets.count), plugin: :redmine_contacts_helpdesk) %>
  <%= sprite_icon('user', l(:text_helpdesk_customer_count, :count => customers.count)) %>
```

### Why It's Slow

1. **`includes(:issue => [:project])`** triggers eager loading with LEFT OUTER JOINs
2. **`.count`** on the loaded relation forces Rails to fetch ALL records into memory before counting
3. **Result:** 17,156 rows × 61 columns = 1,046,516 data points transferred
4. **Network/Memory overhead** causes request to timeout (>120 seconds)

### Generated SQL (Slow)

```sql
SELECT `helpdesk_tickets`.`id` AS t0_r0, 
       `helpdesk_tickets`.`contact_id` AS t0_r1,
       ... (19 columns from helpdesk_tickets)
       `issues`.`id` AS t1_r0,
       `issues`.`project_id` AS t1_r2,
       ... (24 columns from issues)
       `projects`.`id` AS t2_r0,
       `projects`.`name` AS t2_r1,
       ... (18 columns from projects)
FROM `helpdesk_tickets` 
LEFT OUTER JOIN `issues` ON `issues`.`id` = `helpdesk_tickets`.`issue_id` 
LEFT OUTER JOIN `projects` ON `projects`.`id` = `issues`.`project_id` 
WHERE `projects`.`id` = 161
```

**Characteristics:**
- Returns 17,156 rows
- 61 columns per row
- Total data transfer: ~1M+ cell values
- Query execution time: >120 seconds (timeout)

---

## Available Database Indexes

### Issues Table
- ✅ `issues_project_id` on `project_id`
- Additional indexes on status_id, category_id, assigned_to_id, etc.

### HelpdeskTickets Table
- ✅ `index_helpdesk_tickets_on_issue_id_and_contact_id` on `issue_id, contact_id`
- `index_helpdesk_tickets_on_message_id` on `message_id`

**Note:** The existing indexes support fast COUNT queries but are not utilized by the `includes().where().count` pattern.

---

## Why Limited Users Are Affected

Private projects require permission checks that:
1. Cannot be efficiently filtered at the database level with the current query structure
2. Force loading all records into Rails memory for visibility filtering
3. Amplify the data transfer overhead significantly

Admins bypass these checks, which is why they don't experience the hang.

---

## Recommended Fix

Replace the expensive eager-loading queries with simple COUNT queries that utilize existing indexes.

### Proposed Code Change

```erb
<% if User.current.allowed_to?(:view_helpdesk_tickets, @project) %>
  <% ticket_count = HelpdeskTicket.joins(:issue).where(:issues => { :project_id => @project.id }).count %>
  <% customer_count = HelpdeskTicket.joins(:issue).where(:issues => { :project_id => @project.id }).where.not(:contact_id => nil).distinct.count(:contact_id) %>
  <h3><%= l(:label_helpdesk_ticket_plural) %></h3>
  <p><span class="icon icon-helpdesk"><%= sprite_icon('icon-helpdesk', l(:text_helpdesk_ticket_count, :count => ticket_count), plugin: :redmine_contacts_helpdesk) %></span></p>
  <p><span class="icon icon-company-contact"><%= sprite_icon('user', l(:text_helpdesk_customer_count, :count => customer_count)) %></span></p>
  <p><%# link_to(l(:label_report), {:controller => "helpdesk_reports", :action => "tickets_report", :project_id => @project}) %></p>
  <%= call_hook(:view_projects_show_helpdesk_sidebar_bottom, :project => @project) %>
<% end %>
```

### Generated SQL (Fast)

**Ticket Count:**
```sql
SELECT COUNT(*) FROM `helpdesk_tickets` 
INNER JOIN `issues` ON `issues`.`id` = `helpdesk_tickets`.`issue_id` 
WHERE `issues`.`project_id` = 161
```

**Customer Count:**
```sql
SELECT COUNT(DISTINCT `helpdesk_tickets`.`contact_id`) FROM `helpdesk_tickets` 
INNER JOIN `issues` ON `issues`.`id` = `helpdesk_tickets`.`issue_id` 
WHERE `issues`.`project_id` = 161 
AND `helpdesk_tickets`.`contact_id` IS NOT NULL
```

### Performance Improvement

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| **Query Time** | >120s (timeout) | <100ms | >99.9% faster |
| **Data Transfer** | 1M+ values | 2 integers | ~99.9% reduction |
| **Memory Usage** | High (17K objects) | Minimal | Significant |

---

## Implementation Options

### Option 1: Start Script Patch (Temporary)
Add a Ruby patch to `start_redmine.sh` that modifies the partial file on startup:

```bash
HELPDESK_TICKETS_PARTIAL="${REDMINE_PATH}/plugins/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb"
if [ -f "${HELPDESK_TICKETS_PARTIAL}" ]; then
  HELPDESK_TICKETS_PARTIAL="${HELPDESK_TICKETS_PARTIAL}" ruby <<'RUBY'
path = ENV.fetch("HELPDESK_TICKETS_PARTIAL")
content = File.read(path)
original = content.dup

patched = content.gsub(
  '<% if tickets = HelpdeskTicket.includes(:issue => [:project]).where(:projects => {:id => @project}) %>',
  '<% ticket_count = HelpdeskTicket.joins(:issue).where(:issues => { :project_id => @project.id }).count %>'
)

patched = patched.gsub(
  '<% customers = Contact.includes(:tickets => :project).where(:projects => {:id => @project}) %>',
  '<% customer_count = HelpdeskTicket.joins(:issue).where(:issues => { :project_id => @project.id }).where.not(:contact_id => nil).distinct.count(:contact_id) %>'
)

patched = patched.gsub(
  ":count => tickets.count",
  ":count => ticket_count"
)

patched = patched.gsub(
  ":count => customers.count",
  ":count => customer_count"
)

File.write(path, patched) if patched != original
RUBY
fi
```

### Option 2: Plugin Fork/Monkey Patch (Recommended)
Create a proper plugin override or fork the plugin with the optimized queries.

### Option 3: Upstream Fix
Report to RedmineUP and request they optimize the query pattern in future releases.

---

## Runtime Patch Package Snapshot (Maintainers)

The runtime patch package in `config/initializers/runtime_compat.rb` includes broad query optimizations beyond this single helpdesk issue.

- Validated at large scale (17k-issue dataset).
- Primary lane: `TASKMAN_PATCH_*` toggles with guarded fallbacks.
- Core and PRO plugin patches are inventoried in `../docs/patches/PATCHES.md`.

Representative speedups measured during package validation:

- `AGILE_ISSUES_IDS`: ~17.4x
- `RESOURCE_BOOKING_QUERY`: ~25.1x
- `AGILE_DOUBLE_COUNT`: ~16.8x
- `AGILE_SPRINT_PROJECTS`: ~15.6x
- `AGILE_VERSIONS_QUERY`: ~9.4x

For current authoritative toggle inventory and statuses, use:

- `../docs/patches/PATCHES.md`

---

## Testing Recommendations

1. **Before Fix:**
   - Access `/projects/nanyt` as user `bulanmir`
   - Confirm page hangs/times out
   - Monitor nginx logs for 504 Gateway Timeout

2. **After Fix:**
   - Access `/projects/nanyt` as user `bulanmir`
   - Confirm page loads in <5 seconds
   - Verify ticket and customer counts are accurate
   - Test with other private helpdesk projects

3. **SQL Monitoring:**
   - Enable slow query logging in MySQL
   - Set threshold to 1 second
   - Verify no queries exceed threshold after fix

---

## Related Issues

- Project visibility affects query performance
- Private projects with >10K issues are particularly vulnerable
- Similar patterns may exist in other plugin views

---

## References

- File: `plugins/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb`
- Database: MySQL (taskman-mysql-ss-0)
- Plugin: redmine_contacts_helpdesk-4_2_6-pro

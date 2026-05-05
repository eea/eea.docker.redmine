# N+1 Query Pattern Fixes - Documentation

## Overview

This document catalogs all N+1 query patterns found in PRO plugins (`redmine_agile`, `redmine_contacts`, `redmine_contacts_helpdesk`, `redmine_resources`, `redmine_checklists`) and the runtime patches implemented in `runtime_compat.rb` to fix them. Includes Redmine core time_entries optimizations.

## Current Patches (16 Active)

| Toggle | File:Line | Pattern | Fix |
|--------|-----------|---------|-----|
| `AGILE_QUERY` | agile_query.rb:board_issue_statuses | joins through tracker/project | fetches tracker_ids first |
| `AGILE_ISSUES_IDS` | agile_query.rb:640 | `scope.map(&:id)` | `scope.pluck(:id)` |
| `RESOURCE_BOOKING_QUERY` | resource_booking_query.rb:booked_issue_ids | `approved_bookings.map(&:issue_id)` | `pluck(:issue_id)` |
| `RESOURCE_BOOKING_SUM` | resource_booking.rb:total_hours_sum | `to_a.sum(&:total_hours)` | `sum(:total_hours)` |
| `AGILE_DOUBLE_COUNT` | agile_query.rb:issue_board | separate COUNT before SELECT | `limit+1` fetch |
| `AGILE_DESCENDANTS_JOIN` | agile_query.rb:agile_subproject_ids | `select {...}.map(&:id)` | JOIN + pluck |
| `AGILE_SPRINT_PROJECTS` | agile_query.rb:819 | `map.map.flatten.uniq` | JOIN + pluck |
| `HELPDESK_COLLECTOR` | helpdesk_data_collector_busiest_time.rb | `map.map(&:id)` | JOIN + pluck |
| `AGILE_SPRINT_HOURS_SUM` | agile_sprints_controller.rb:36-38 | `issues.map(&:hours).compact.sum` | `issues.sum(:hours)` |
| `CONTACTS_IDS` | contacts_controller.rb:205 | `contacts.map(&:id).join` | `contacts.pluck(:id).join` |
| `HELPDESK_PROJECT_CHILDREN` | helpdesk_ticket.rb:270 | `children.select {...}.map(&:id)` | JOIN + pluck |
| `RESOURCE_BOOKING_BLANK_ISSUE` | week_plan.rb:94 | `select { |rb| rb.issue.blank? }.map(&:project_id)` | `where(issue_id: nil).pluck(:project_id)` |
| `DEAL_LINES_SUM` | deal.rb:262-270 | `lines.inject { |sum, l| sum + l.amount }` | `lines.sum(:amount)` |
| `CONTACT_NOTES_ATTACHMENTS` | contact.rb:289 | `notes.map(&:id)` in query | `notes.pluck(:id)` |
| `TIME_ENTRY_CUSTOM_VALUES` | time_entry_query.rb:results_scope | custom_values N+1 per time_entry | preload(:custom_values) |
| `TIME_ENTRY_PROJECT_MODULES` | timelog_controller.rb:index | enabled_modules N+1 per project | batch preload |
| `TIME_ENTRY_SUM_HOURS` | time_entry_query.rb:default_total_hours | separate SUM query | cached calculation |

## Additional Patches to Implement

### 1. AGILE_SPRINT_HOURS_SUM

**File:** `redmine_agile/app/controllers/agile_sprints_controller.rb:36-38`

**Original:**
```ruby
@estimated_hours = issues.map(&:estimated_hours).compact.sum
@spent_hours = issues.map(&:spent_hours).compact.sum
@story_points = issues.map(&:story_points).compact.sum
all_done_ratio = issues.map(&:done_ratio)
```

**Problem:** Loads all Issue records into Ruby memory just to sum 3 fields.

**Fix:** Use DB aggregation
```ruby
@estimated_hours = issues.sum(:estimated_hours)
@spent_hours = issues.sum(:spent_hours)
@story_points = issues.sum(:story_points)
all_done_ratio = issues.average(:done_ratio)
```

---

### 2. CONTACTS_IDS

**File:** `redmine_contacts/app/controllers/contacts_controller.rb:205`

**Original:**
```ruby
cond << "and (#{Contact.table_name}.id in (#{contacts.any? ? contacts.map(&:id).join(', ') : 'NULL'})"
```

**Problem:** `map(&:id)` loads full Contact records just to get IDs.

**Fix:** `pluck(:id)` directly queries IDs without loading records.

---

### 3. DEALS_IDS

**File:** `redmine_contacts/app/controllers/contacts_controller.rb:207`

**Original:**
```ruby
cond << " or #{Deal.table_name}.id in (#{deals.any? ? deals.map(&:id).join(', ') : 'NULL'}))"
```

**Fix:** Same as CONTACTS_IDS - use `pluck(:id)`.

---

### 4. CONTACTS_TAG_LIST_UNION

**File:** `redmine_contacts/app/controllers/contacts_controller.rb:249`

**Original:**
```ruby
@tag_list = Redmineup::TagList.from(@contacts.map(&:tag_list).inject { |memo, t| memo | t })
```

**Problem:** Loads all contacts' tag lists into Ruby, then unions them.

**Fix:** Single query to get all tags for contacts:
```ruby
@tag_list = Redmineup::TagList.from(@contacts.flat_map(&:tag_list).uniq)
```

---

### 5. DEALS_CONTROLLER_INJECT

**File:** `redmine_contacts/app/controllers/deals_controller.rb:224-227`

**Original:**
```ruby
@available_statuses = @projects.map(&:deal_statuses).inject { |memo, w| memo & w }
@available_categories = @projects.map(&:deal_categories).inject { |memo, w| memo & w }
@assignables = @projects.map(&:assignable_users).inject { |memo, a| memo & a }
```

**Problem:** Each `map` runs a separate query per project, then intersects in Ruby.

**Fix:** Single query with proper set operations.

---

### 6. CONTACTS_CONTROLLER_INJECT

**File:** `redmine_contacts/app/controllers/contacts_controller.rb:228-232`

**Original:**
```ruby
@can[:edit] = @contacts.collect { |c| c.editable? }.inject { |memo, d| memo && d }
@can[:delete] = @contacts.collect { |c| c.deletable? }.inject { |memo, d| memo && d }
@can[:send_mails] = @contacts.collect { |c| c.send_mail_allowed? && !c.primary_email.blank? }.inject { |memo, d| memo && d }
```

**Problem:** Calls expensive method on each contact in Ruby.

**Fix:** Use `all?` or `any?` with early termination:
```ruby
@can[:edit] = @contacts.all?(&:editable?)
@can[:delete] = @contacts.all?(&:deletable?)
@can[:send_mails] = @contacts.all? { |c| c.send_mail_allowed? && !c.primary_email.blank? }
```

---

### 7. HELP DESK_PROJECT_CHILDREN

**File:** `redmine_contacts_helpdesk/app/models/helpdesk_ticket.rb:270`

**Original:**
```ruby
pids = [project.id] + project.children.select { |ch| ch.module_enabled?(:contacts_helpdesk) }.map(&:id)
```

**Fix:** Use where with module check:
```ruby
pids = [project.id] + project.children.joins(:enabled_modules)
                                 .where(enabled_modules: { name: :contacts_helpdesk })
                                 .pluck(:id)
```

---

### 8. RESOURCE_BOOKING_SELECT_BLANK

**Files:** `redmine_resources/charts/helpers/week_plan.rb:94`, `month_plan.rb:88`, `plan.rb:114`

**Original:**
```ruby
booked_project_ids = @resource_bookings.select { |rb| rb.issue.blank? }.map(&:project_id)
```

**Fix:**
```ruby
booked_project_ids = @resource_bookings.where(issue_id: nil).pluck(:project_id)
```

---

### 9. DEAL_LINES_SUM

**File:** `redmine_contacts/app/models/deal.rb:262-270`

**Original:**
```ruby
lines.select { |l| !l.marked_for_destruction? }.inject(0) { |sum, l| sum + l.tax_amount }
lines.select { |l| !l.marked_for_destruction? }.inject(0) { |sum, l| sum + l.total }
lines.inject(0) { |sum, l| sum + (l.product.blank? ? 0 : l.quantity) }
```

**Fix:** Use DB sum with where condition:
```ruby
lines.where(marked_for_destruction: false).sum(:tax_amount)
lines.where(marked_for_destruction: false).sum(:total)
lines.sum("CASE WHEN product_id IS NULL THEN 0 ELSE quantity END")
```

---

### 10. CONTACT_NOTES_ATTACHMENTS

**File:** `redmine_contacts/app/models/contact.rb:289`

**Original:**
```ruby
@contact_attachments ||= Attachment.where(:container_type => 'Note', :container_id => notes.map(&:id)).order(:created_on)
```

**Fix:**
```ruby
@contact_attachments ||= Attachment.where(:container_type => 'Note', :container_id => notes.pluck(:id)).order(:created_on)
```

---

## Pattern Categories

### 1. `map(&:id)` → `pluck(:id)`
The most common pattern. `map(&:id)` loads full ActiveRecord objects then extracts IDs. `pluck(:id)` queries IDs directly.

### 2. `map(&:attr).sum` → `sum(:attr)`
Loads all records to extract one field and sum in Ruby. `sum(:attr)` performs DB aggregation.

### 3. `select {...}.map(&:id)` → `where(...).pluck(:id)`
Ruby filtering then ID extraction. Should be done in DB.

### 4. `collection.map {...}.inject` → `all?`/`any?`
Checking if all/any items match a condition. Use `all?`/`any?` for early termination.

### 5. `map(&:association).inject` → JOIN + single query
Each `map` runs N queries. Should join once and operate on DB.

## Files Analyzed

- `/addons/current/plugins/redmine_agile/app/` (models, controllers, helpers, views)
- `/addons/current/plugins/redmine_contacts/app/` (models, controllers, helpers, views)
- `/addons/current/plugins/redmine_contacts_helpdesk/app/` (models, controllers)
- `/addons/current/plugins/redmine_resources/app/` (models, helpers, views)
- `/addons/current/plugins/redmine_checklists/app/` (helpers)

## Not Analyzed (Test Files Excluded)

- All `test/` directories
- All `spec/` directories

## Validation

Run the validation script in Docker:
```bash
docker compose -f test/docker-compose.yml -f addons/pro.yml run --rm migrate
# Then in container:
RAILS_ENV=test SECRET_KEY_BASE=test bundle exec ruby /tmp/full_patch_validation.rb
```
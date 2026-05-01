# Plugin Query Optimization Tracking

**Last Updated:** 2026-05-01
**Total Optimizations:** 11
**Status Summary:** 11 DONE, 0 IN_PROGRESS, 0 PENDING

---

## Overview

This document tracks all 11 planned and completed query optimizations for Redmine plugins. Each optimization replaces expensive `includes()`, `map(&:id)`, or N+1 query patterns with indexed `pluck()`, `joins()`, or `count()` queries.

---

## Optimization Table

| # | Plugin | File | Line | Current Code | Suggested Fix | Impact | Status |
|---|--------|------|------|--------------|---------------|--------|--------|
| 1 | redmine_contacts_helpdesk | app/views/projects/_helpdesk_tickets.html.erb | 45 | `HelpdeskTicket.includes(:issue => [:project]).where(...)` | `HelpdeskTicket.joins(:issue).where(...)` | HIGH | DONE |
| 2 | redmine_contacts_helpdesk | app/views/projects/_helpdesk_tickets.html.erb | 46 | `Contact.includes(:tickets => :project).where(...)` | `HelpdeskTicket.joins(:issue).where(...).distinct.count(:contact_id)` | HIGH | DONE |
| 3 | redmine_agile | agile_query.rb | 640 | `scope.map(&:id)` | `scope.pluck(:id)` | HIGH | DONE |
| 4 | redmine_agile | agile_query.rb | 726 | COUNT + SELECT double query | limit+1 fetch and truncate | HIGH | DONE |
| 5 | redmine_agile | agile_query.rb | 770 | `descendants.select { ... }.map(&:id)` | descendants JOIN enabled_modules + `pluck(:id)` | HIGH | DONE |
| 6 | redmine_agile | agile_query.rb | 819 | nested `map(&:shared_projects)...flatten.uniq` | JOIN shared_projects + `pluck('projects.id')` | HIGH | DONE |
| 7 | redmine_contacts_helpdesk | helpdesk_data_collector_busiest_time.rb | 149 | `.map(&:customer).map(&:id)` | `joins(:customer).pluck(Contact.id)` | HIGH | DONE |
| 8 | redmine_resources | resource_booking.rb | 215 | `to_a.sum(&:total_hours)` | `sum(:total_hours)` | MEDIUM | DONE |
| 9 | redmine_contacts | app/views/deals/_deals_statistics.html.erb | 12 | status loop `.count` per row | controller pre-aggregation hash | HIGH | DONE |
| 10 | redmine_contacts | app/views/deals/_board_deals_counts.html.erb | 4 | status loop `.count` per row | controller pre-aggregation hash | HIGH | DONE |
| 11 | redmine_resources | app/views/resource_bookings/charts/_utilization_report.html.erb | 46 | `roles_for_project` in nested loop | controller pre-load roles lookup | MEDIUM | DONE |

---

## Completed Optimizations

### OPT-001: Helpdesk Ticket Count
- **File:** `plugins/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb`
- **Line:** ~45
- **Before:**
  ```erb
  <% if tickets = HelpdeskTicket.includes(:issue => [:project]).where(:projects => {:id => @project}) %>
  ```
- **After:**
  ```erb
  <% ticket_count = HelpdeskTicket.joins(:issue).where(:issues => { :project_id => @project.id }).count %>
  ```
- **Performance:** >120s → <100ms (>99.9% improvement)
- **Implemented:** Via `redmine_eea_patches` plugin

### OPT-002: Helpdesk Customer Count
- **File:** `plugins/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb`
- **Line:** ~46
- **Before:**
  ```erb
  <% customers = Contact.includes(:tickets => :project).where(:projects => {:id => @project}) %>
  ```
- **After:**
  ```erb
  <% customer_count = HelpdeskTicket.joins(:issue).where(:issues => { :project_id => @project.id }).where.not(:contact_id => nil).distinct.count(:contact_id) %>
  ```
- **Performance:** >120s → <100ms (>99.9% improvement)
- **Implemented:** Via `redmine_eea_patches` plugin

### OPT-003/004/008: Runtime compat monkey patches
- **Task 1 (agile_query.rb:640):** DONE - Patched via `runtime_compat.rb` `TASKMAN_PATCH_AGILE_ISSUES_IDS`
- **Task 2 (resource_booking_query.rb:56):** DONE - Patched via `runtime_compat.rb` `TASKMAN_PATCH_RESOURCE_BOOKING_QUERY`
- **Task 8 (resource_booking.rb:215):** DONE - Patched via `runtime_compat.rb` `TASKMAN_PATCH_RESOURCE_BOOKING_SUM`
- **Task 4 (agile_query.rb:726):** DONE - Patched via `TASKMAN_PATCH_AGILE_DOUBLE_COUNT`
- **Task 5 (agile_query.rb:770):** DONE - Patched via `TASKMAN_PATCH_AGILE_DESCENDANTS_JOIN`
- **Task 6 (agile_query.rb:819):** DONE - Patched via `TASKMAN_PATCH_AGILE_SPRINT_PROJECTS`
- **Task 7 (helpdesk_data_collector:149):** DONE - Patched via `TASKMAN_PATCH_HELPDESK_COLLECTOR`
- **Task 3 (_sprints.html.erb:7):** DONE - Patched via `TASKMAN_PATCH_AGILE_SPRINTS_CACHE` (helper memoization)
- **Task 9 (_deals_statistics.html.erb:12):** DONE - Patched via `TASKMAN_PATCH_DEALS_STATS` (controller pre-aggregation)
- **Task 10 (_board_deals_counts.html.erb:4):** DONE - Patched via `TASKMAN_PATCH_BOARD_DEALS` (controller pre-aggregation)
- **Task 11 (_utilization_report.html.erb:46):** DONE - Patched via `TASKMAN_PATCH_UTILIZATION_ROLES` (controller pre-load)

---

## Pending Optimizations

All planned optimizations are implemented.

---

## Implementation Guide

### For New Optimizations

1. **Identify the slow query** - Look for:
   - `includes()` followed by `.count`
   - `scope.map(&:id)`
   - N+1 patterns (loops with individual queries)

2. **Measure baseline** - Use benchmark script:
   ```ruby
   time = Benchmark.measure do
     # original slow query
   end
   puts "Original: #{time.real}s"
   ```

3. **Apply optimization** - Replace with indexed alternative:
   - `includes().count` → `joins().count`
   - `map(&:id)` → `pluck(:id)`
   - `includes()` → `joins()` + `select()`

4. **Verify results** - Ensure:
   - Same data is returned
   - Performance improved
   - No regressions in edge cases

5. **Update this document** - Mark as DONE with implementation date

---

## Testing

Run the performance test seed:
```bash
rails runner db/seeds/performance_test_data.rb
```

Run benchmarks:
```bash
ruby performance_findings/benchmark.rb
```

---

## See Also

- [performance_findings/README.md](./README.md) - Complete investigation report
- [performance_findings/FIX_IMPLEMENTATION.md](./FIX_IMPLEMENTATION.md) - Helpdesk fix details
- [performance_findings/TESTING_GUIDE.md](./TESTING_GUIDE.md) - Validation procedures

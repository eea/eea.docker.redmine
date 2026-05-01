# Plugin Query Optimization Tracking

**Last Updated:** 2026-05-01
**Total Optimizations:** 11
**Status Summary:** 1 DONE, 0 IN_PROGRESS, 10 PENDING

---

## Overview

This document tracks all 11 planned and completed query optimizations for Redmine plugins. Each optimization replaces expensive `includes()`, `map(&:id)`, or N+1 query patterns with indexed `pluck()`, `joins()`, or `count()` queries.

---

## Optimization Table

| # | Plugin | File | Line | Current Code | Suggested Fix | Impact | Status |
|---|--------|------|------|--------------|---------------|--------|--------|
| 1 | redmine_contacts_helpdesk | app/views/projects/_helpdesk_tickets.html.erb | 45 | `HelpdeskTicket.includes(:issue => [:project]).where(...)` | `HelpdeskTicket.joins(:issue).where(...)` | HIGH | DONE |
| 2 | redmine_contacts_helpdesk | app/views/projects/_helpdesk_tickets.html.erb | 46 | `Contact.includes(:tickets => :project).where(...)` | `HelpdeskTicket.joins(:issue).where(...).distinct.count(:contact_id)` | HIGH | DONE |
| 3 | redmine_agile | agile_query.rb | 640 | `scope.map(&:id)` | `scope.pluck(:id)` | HIGH | PENDING |
| 4 | redmine_agile | agile_query.rb | TBD | `scope.map(&:id)` | `scope.pluck(:id)` | HIGH | PENDING |
| 5 | redmine_crm | contacts_controller.rb | TBD | `Contact.includes(:tickets).where(...)` | `Contact.joins(:tickets).where(...)` | MEDIUM | PENDING |
| 6 | redmine_crm | deals_controller.rb | TBD | `Deal.includes(:contact).where(...)` | `Deal.joins(:contact).where(...)` | MEDIUM | PENDING |
| 7 | redmine_checklists | checklist_query.rb | TBD | `.map(&:id)` | `.pluck(:id)` | MEDIUM | PENDING |
| 8 | redmine_resources | resource_bookings_controller.rb | TBD | `ResourceBooking.includes(:user, :project)` | `ResourceBooking.joins(:user, :project)` | MEDIUM | PENDING |
| 9 | redmine_reporter | reporter_controller.rb | TBD | `Issue.includes(:tracker, :status, :project)` | `Issue.select(:id, :project_id, :tracker_id, :status_id)` | MEDIUM | PENDING |
| 10 | redmine_contacts | contacts_query.rb | TBD | `.map(&:id)` | `.pluck(:id)` | MEDIUM | PENDING |
| 11 | redmine_zenedit | zenedit_controller.rb | TBD | `WikiPage.includes(:content).where(...)` | `WikiPage.joins(:content).where(...)` | MEDIUM | PENDING |

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

---

## Pending Optimizations

### OPT-003: AgileQuery board_issue_statuses (Tracker IDs)
- **File:** `plugins/redmine_agile/.../agile_query.rb`
- **Line:** 640
- **Problem:** `scope.map(&:id)` loads all IssueStatus objects just to get IDs
- **Suggested Fix:**
  ```ruby
  # Before
  tracker_ids = @issue_scope.map(&:tracker_id).compact.uniq

  # After
  tracker_ids = @issue_scope.distinct.pluck(:tracker_id).compact
  ```
- **Impact:** HIGH - Affects board rendering for projects with many trackers

### OPT-004: AgileQuery board_issue_statuses (Status IDs)
- **File:** `plugins/redmine_agile/.../agile_query.rb`
- **Line:** TBD
- **Problem:** WorkflowTransition query uses `.map(&:id)` pattern
- **Suggested Fix:**
  ```ruby
  # Before
  status_ids = transitions.map(&:new_status_id)

  # After
  status_ids = transitions.pluck(:new_status_id)
  ```
- **Impact:** HIGH

### OPT-005: CRM Contacts List Pagination
- **File:** `plugins/redmine_crm/.../contacts_controller.rb`
- **Problem:** Loads all contacts with heavy includes
- **Suggested Fix:** Use pagination with `limit/offset` and `joins` instead of `includes`
- **Impact:** MEDIUM

### OPT-006: CRM Deals List Optimization
- **File:** `plugins/redmine_crm/.../deals_controller.rb`
- **Problem:** Deal listing uses expensive eager loading
- **Suggested Fix:** Replace `includes(:contact)` with `joins(:contact)` and selective loading
- **Impact:** MEDIUM

### OPT-007: Checklists Issue Items
- **File:** `plugins/redmine_checklists/.../checklist_query.rb`
- **Problem:** `.map(&:id)` on checklist items
- **Suggested Fix:** Replace with `.pluck(:id)`
- **Impact:** MEDIUM

### OPT-008: Resource Bookings Query
- **File:** `plugins/redmine_resources/.../resource_bookings_controller.rb`
- **Problem:** `includes(:user, :project)` loads full associations
- **Suggested Fix:** Use `joins` and select only needed columns
- **Impact:** MEDIUM

### OPT-009: Reporter Issue Query
- **File:** `plugins/redmine_reporter/.../reporter_controller.rb`
- **Problem:** Issue listing loads all columns via `includes`
- **Suggested Fix:** Use `select()` to limit columns
- **Impact:** MEDIUM

### OPT-010: Contacts Query Optimization
- **File:** `plugins/redmine_crm/.../contacts_query.rb`
- **Problem:** `.map(&:id)` pattern in contact queries
- **Suggested Fix:** Replace with `.pluck(:id)`
- **Impact:** MEDIUM

### OPT-011: ZenEdit Wiki Pages
- **File:** `plugins/redmine_zenedit/.../zenedit_controller.rb`
- **Problem:** `includes(:content)` loads full wiki content
- **Suggested Fix:** Use `joins` for counting, `select` for listing
- **Impact:** MEDIUM

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

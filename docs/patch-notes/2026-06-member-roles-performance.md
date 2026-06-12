# Patch Notes — Member Roles Performance (2026-06)

**Date:** 2026-06-12
**Audience:** Taskman maintainers, Helm operators
**Scope:** Three new runtime patches + bug fixes in 6 existing patches + 2 patches deleted

---

## Summary

Projects with deep inheritance hierarchies (many `member_roles` rows per member from ancestor projects) caused two pages to time out:

- `/projects/:id` show page — significant improvement
- `/projects/:id/settings/members` — significant improvement

Root cause: multiple code paths loaded all inherited `member_roles` rows via JOIN or IN-clause queries. The fix uses `SELECT DISTINCT member_id, role_id` on a composite covering index, which collapses many rows to a small set of unique role assignments.

---

## New patches

### SORTED_SCOPE (`TASKMAN_PATCH_SORTED_SCOPE=1`)

`Member.sorted` is a Rails scope used in the settings/members view. It was defined with `includes(:member_roles, :roles, :principal)` — because `:roles` is `has_many :through :member_roles`, this forces a full JOIN on all inherited member_roles rows.

Replaced with a correlated scalar subquery for sort order. Only activates inside `ProjectsController#settings` (guarded by a thread-local set by `MEMBER_ROLES_SETTINGS_BULK_PRELOAD`). Falls back to the original scope everywhere else — no other caller is affected.

### MEMBER_ROLES_SETTINGS_BULK_PRELOAD (`TASKMAN_PATCH_MEMBER_ROLES_SETTINGS_BULK_PRELOAD`, default on)

Patches `ProjectsController#settings` to pre-load all data needed by the 438-member view loop before the view renders. Two DISTINCT queries are kept separate (not combined into one GROUP BY) because adding `inherited_from` to the GROUP BY would push MySQL off the `(member_id, role_id)` covering index — the covering index scan is only possible when selecting only the indexed columns.

Sets three thread-locals consumed by patched model methods during the request. All are cleared after every request by an `around_action` on `ApplicationController`.

### PROJECT_MEMBERS_PRELOAD (`TASKMAN_PATCH_PROJECT_MEMBERS_PRELOAD=1`) — updated

Previously used `includes(member_roles: :role)` which still loaded all inherited rows. Rewritten to use the same DISTINCT covering-index approach. Show page: significant improvement on affected projects.

---

## Bug fixes in existing patches

These patches had bugs that would have caused runtime errors or silent failures. All were disabled before this session; fixed and re-enabled.

| Patch | Bug | Fix |
|---|---|---|
| `CONTACTS_IDS` | `def index; super; end` — did nothing | **Deleted entirely** |
| `PROJECT_MEMBERS_COUNT` | `respond_to?(:member_roles_count_cache)` always false — entire patch was a no-op | **Deleted entirely** |
| `DEAL_LINES_SUM` | `lines.where(marked_for_destruction: false)` — `marked_for_destruction` is not a DB column, raises `StatementInvalid` | Changed to `lines.sum(:col)` |
| `AGILE_DOUBLE_COUNT` | `rescue ArgumentError; super()` — drops original method args | Changed to `super(*args, &block)` |
| `CONTACT_GROUPS_IDS` | `user_ids = [usr.id] + usr.groups.pluck(:id)` — computed, never used, wasted a query | Removed dead line |
| `AGILE_SPRINT_HOURS_SUM` | `if @issues.any?` — `NoMethodError` if `super` sets `@issues = nil` | Changed to `@issues&.any?` |
| `TIME_ENTRY_SUM_HOURS` | `!responseable?` — method may not exist on all `TimeEntryQuery` instances | Guarded with `respond_to?` |

---

## Patch state after this session

**Active (21):** AGILE_QUERY, AGILE_ISSUES_IDS, AGILE_DOUBLE_COUNT, AGILE_DESCENDANTS_JOIN, AGILE_SPRINT_PROJECTS, AGILE_SPRINT_HOURS_SUM, AGILE_VERSIONS_QUERY, AGILE_SPRINTS_QUERY, HELPDESK_COLLECTOR, HELPDESK_PROJECT_CHILDREN, RESOURCE_BOOKING_QUERY, RESOURCE_BOOKING_BLANK_ISSUE, DEAL_LINES_SUM, CONTACT_NOTES_ATTACHMENTS, CONTACT_GROUPS_IDS, TIME_ENTRY_CUSTOM_VALUES, TIME_ENTRY_PROJECT_MODULES, TIME_ENTRY_SUM_HOURS, PROJECT_MEMBERS_PRELOAD, SORTED_SCOPE, MEMBER_ROLES_SETTINGS_BULK_PRELOAD, ACTIVITY_AUTHOR_PRELOAD

**Disabled (3):** USER_ROLES_PRELOAD, CONTACTS_CONTROLLER_CAN, WIKI_LINKS_MAIN_APP — see `docs/patches/CURRENT_PATCHES.md` for risk notes on each.

---

## K8s probe changes

`startupProbe.initialDelaySeconds` reduced 60s → 20s. With `FAST_BOOT=1` and YJIT, Puma typically binds port 3000 within 15–25 seconds. The old 60s floor was dead waiting time.

| Probe | Before | After |
|---|---|---|
| `startupProbe.initialDelaySeconds` | 60s | 20s |
| `startupProbe.periodSeconds` | 10s | 5s |
| `startupProbe.failureThreshold` | 30 | 60 |
| `readinessProbe.periodSeconds` | 10s | 5s |

---

## For plugin developers

If you maintain `redmine_agile`, `redmine_contacts`, `redmine_resources`, or `redmine_contacts_helpdesk`: the patches in `runtime_compat.rb` are workarounds for patterns in your plugins. See `docs/patches/CURRENT_PATCHES.md` for the Before/After code of each patch. The ideal long-term fix is to address these patterns upstream so the patches can be removed.

The three patches most worth upstreaming:
1. **AGILE_ISSUES_IDS** — `issue_scope.map(&:id)` → `pluck(:id)` (one-liner)
2. **AGILE_DESCENDANTS_JOIN** — Ruby `select/map` → SQL `joins(:enabled_modules).pluck(:id)`
3. **AGILE_SPRINT_PROJECTS** — nested `map/flatten/uniq` → SQL `joins + pluck`

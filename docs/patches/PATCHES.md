# Taskman Runtime Patch Manifest

Canonical inventory for runtime patches.

> **Source-of-truth policy:** Full patch descriptions live in `docs/patches/CURRENT_PATCHES.md`. This file is the status/toggle inventory only.

- Detailed patch catalog: `docs/patches/CURRENT_PATCHES.md`
- Operations guide (enable/disable/rollback): `docs/patches/PATCH_OPERATIONS.md` *(or see inline below)*

---

## Active Patches

All patches are in `config/initializers/runtime_compat.rb`, deployed via ConfigMap `taskman-runtime-compat`. Toggle with `TASKMAN_PATCH_<NAME>=1|0` env var — no image rebuild required.

| Patch | Toggle | Status | What it fixes |
|---|---|---|---|
| AGILE_QUERY | `TASKMAN_PATCH_AGILE_QUERY` | **on** | Board status lookup — 2-step pluck vs JOIN through workflows |
| AGILE_ISSUES_IDS | `TASKMAN_PATCH_AGILE_ISSUES_IDS` | **on** | `pluck(:id)` vs `map(&:id)` |
| RESOURCE_BOOKING_QUERY | `TASKMAN_PATCH_RESOURCE_BOOKING_QUERY` | **on** | Booked issue IDs — pluck vs map |
| AGILE_DOUBLE_COUNT | `TASKMAN_PATCH_AGILE_DOUBLE_COUNT` | **on** | limit+1 fetch vs separate COUNT query |
| AGILE_DESCENDANTS_JOIN | `TASKMAN_PATCH_AGILE_DESCENDANTS_JOIN` | **on** | SQL JOIN vs Ruby select/map for descendants |
| AGILE_SPRINT_PROJECTS | `TASKMAN_PATCH_AGILE_SPRINT_PROJECTS` | **on** | SQL JOIN vs nested map chain |
| HELPDESK_COLLECTOR | `TASKMAN_PATCH_HELPDESK_COLLECTOR` | **on** | Customer IDs — joins + pluck vs map |
| AGILE_SPRINT_HOURS_SUM | `TASKMAN_PATCH_AGILE_SPRINT_HOURS_SUM` | **on** | SQL SUM vs loading records |
| HELPDESK_PROJECT_CHILDREN | `TASKMAN_PATCH_HELPDESK_PROJECT_CHILDREN` | **on** | SQL JOIN vs Ruby select for child projects |
| RESOURCE_BOOKING_BLANK_ISSUE | `TASKMAN_PATCH_RESOURCE_BOOKING_BLANK_ISSUE` | **on** | where(issue_id: nil).pluck vs Ruby select |
| DEAL_LINES_SUM | `TASKMAN_PATCH_DEAL_LINES_SUM` | **on** | SQL SUM vs loading all lines |
| CONTACT_NOTES_ATTACHMENTS | `TASKMAN_PATCH_CONTACT_NOTES_ATTACHMENTS` | **on** | notes.pluck(:id) vs notes.map(&:id) |
| CONTACT_GROUPS_IDS | `TASKMAN_PATCH_CONTACT_GROUPS_IDS` | **on** | Contact visibility — scoped AR query |
| AGILE_VERSIONS_QUERY | `TASKMAN_PATCH_AGILE_VERSIONS_QUERY` | **on** | Roadmap tracker IDs — pluck vs map |
| AGILE_SPRINTS_QUERY | `TASKMAN_PATCH_AGILE_SPRINTS_QUERY` | **on** | Sprint project descendants — pluck vs map |
| TIME_ENTRY_CUSTOM_VALUES | `TASKMAN_PATCH_TIME_ENTRY_CUSTOM_VALUES` | **on** | Preload custom_values to avoid N+1 |
| TIME_ENTRY_PROJECT_MODULES | `TASKMAN_PATCH_TIME_ENTRY_PROJECT_MODULES` | **on** | Bulk preload enabled_modules |
| TIME_ENTRY_SUM_HOURS | `TASKMAN_PATCH_TIME_ENTRY_SUM_HOURS` | **on** | Cached SUM(:hours) |
| PROJECT_MEMBERS_PRELOAD | `TASKMAN_PATCH_PROJECT_MEMBERS_PRELOAD` | **on** | Show page: DISTINCT bulk load for principals_by_role |
| SORTED_SCOPE | `TASKMAN_PATCH_SORTED_SCOPE` | **on** | Settings/members: correlated subquery vs 210K JOIN |
| MEMBER_ROLES_SETTINGS_BULK_PRELOAD | `TASKMAN_PATCH_MEMBER_ROLES_SETTINGS_BULK_PRELOAD` | **on** (default) | Settings/members: pre-load roles/deletable before view |
| ACTIVITY_AUTHOR_PRELOAD | `TASKMAN_PATCH_ACTIVITY_AUTHOR_PRELOAD` | **on** (default) | Bulk preload event authors |

---

## Disabled Patches (design-level risks)

| Patch | Toggle | Reason |
|---|---|---|
| USER_ROLES_PRELOAD | `TASKMAN_PATCH_USER_ROLES_PRELOAD=0` | Full reimplementation of `User#roles` — security-critical, controls all permissions. Enable only after testing. |
| CONTACTS_CONTROLLER_CAN | `TASKMAN_PATCH_CONTACTS_CONTROLLER_CAN=0` | Overwrites `@can` flags set by `super` — may bypass permission checks. |
| WIKI_LINKS_MAIN_APP | `TASKMAN_PATCH_WIKI_LINKS_MAIN_APP=0` | Full reimplementation of `parse_wiki_links` — drifts on Redmine upgrades. Re-enable if AI helper routing bug recurs. |

---

## Deleted Patches

| Patch | Reason |
|---|---|
| CONTACTS_IDS | Dead code — `def index; super; end` did nothing. Removed. |
| PROJECT_MEMBERS_COUNT | Dead code — `respond_to?(:member_roles_count_cache)` always false. Removed. |

---

## Plugin View Fixes (not runtime_compat)

| Fix | Location | What it fixes |
|---|---|---|
| Helpdesk sidebar count | `plugins/zzzz_eea_patches/` view override | `includes(...).count` loading full relations → `JOIN + COUNT(*)` |
| Banner engine routes | `plugins/zzzz_eea_patches/` view override | Banner URLs failing inside engine scope (AI helper) |

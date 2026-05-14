# Taskman Runtime Patch Manifest

Canonical inventory for runtime patches and stale archives.

> Source-of-truth policy:
> - Full patch descriptions (Problem/Solution/Code/Performance/Affected Projects) live only in `docs/patches/CURRENT_PATCHES.md`.
> - Other docs should reference that file, not duplicate patch content.

- Detailed patch catalog (normalized format): `docs/patches/CURRENT_PATCHES.md`

## Changelog

### 2026-05-14

- Reviewed and normalized patch documentation across repo.
- Added complete per-patch catalog in standardized format:
  - `docs/patches/CURRENT_PATCHES.md`
- Converted legacy N+1 patch document into canonical pointer:
  - `performance_findings/N_PLUS_ONE_PATTERNS.md`

### 2026-05-12

- Standardized patch catalog added in required format:
  - `docs/patches/CURRENT_PATCHES.md`

- Detailed plugin-developer patch notes added:
  - `docs/patch-notes/2026-05-runtime-and-plugin-developer-notes.md`
- Email-ready plugin-maintainer summary added:
  - `docs/patch-notes/archive/2026-05-plugin-developers-email-ready.md`
- RedmineUP support request email draft added:
  - `docs/patch-notes/archive/2026-05-redmineup-support-email-ready.md`

- Added `ACTIVITY_AUTHOR_PRELOAD` runtime patch in `config/initializers/runtime_compat.rb`.
  - Toggle: `TASKMAN_PATCH_ACTIVITY_AUTHOR_PRELOAD` (default: enabled)
  - Goal: reduce `/projects/:id/activity` author-related N+1 by preloading `:author` in `Redmine::Activity::Fetcher#events`.
- Added standalone file `config/initializers/activity_author_preload_patch.rb` during iteration.
  - Note: runtime behavior is governed by `runtime_compat.rb`; keep a single canonical load path to avoid duplicate patch application.
- Validation summary:
  - Runtime patch status and static audit scripts passed (`performance_findings/scripts/runtime_patch_status.rb`, `performance_findings/scripts/audit_patches.rb`).
  - In Kubernetes, effective runtime file can be overridden by `runtime-compat-config` ConfigMap mount; image-only updates are not sufficient when this mount is active.

## How to read this file

- **Status**
  - `active`: patch code exists in `config/initializers/runtime_compat.rb`
  - `stale`: patch archived under `config/stale/` and not auto-loaded
- **Toggle** maps to env var: `TASKMAN_PATCH_<TOGGLE>`
- **Owner** defaults to `taskman-maintainers` until per-patch ownership is assigned

## Active Patches

| Patch | Toggle | Status | Source | Owner | Notes |
|---|---|---|---|---|---|
| AGILE_QUERY | TASKMAN_PATCH_AGILE_QUERY | active | `config/initializers/runtime_compat.rb:27` | taskman-maintainers | Agile query lookup rewrite |
| AGILE_ISSUES_IDS | TASKMAN_PATCH_AGILE_ISSUES_IDS | active | `config/initializers/runtime_compat.rb:64` | taskman-maintainers | `pluck(:id)` path |
| RESOURCE_BOOKING_QUERY | TASKMAN_PATCH_RESOURCE_BOOKING_QUERY | active | `config/initializers/runtime_compat.rb:88` | taskman-maintainers | Booked issue IDs query |
| AGILE_DOUBLE_COUNT | TASKMAN_PATCH_AGILE_DOUBLE_COUNT | active | `config/initializers/runtime_compat.rb:112` | taskman-maintainers | limit+1 fetch strategy |
| AGILE_DESCENDANTS_JOIN | TASKMAN_PATCH_AGILE_DESCENDANTS_JOIN | active | `config/initializers/runtime_compat.rb:141` | taskman-maintainers | SQL join for descendants |
| AGILE_SPRINT_PROJECTS | TASKMAN_PATCH_AGILE_SPRINT_PROJECTS | active | `config/initializers/runtime_compat.rb:168` | taskman-maintainers | Sprint project IDs via SQL |
| HELPDESK_COLLECTOR | TASKMAN_PATCH_HELPDESK_COLLECTOR | active | `config/initializers/runtime_compat.rb:195` | taskman-maintainers | Helpdesk collector query |
| AGILE_SPRINT_HOURS_SUM | TASKMAN_PATCH_AGILE_SPRINT_HOURS_SUM | active | `config/initializers/runtime_compat.rb:215` | taskman-maintainers | Sprint sums in controller |
| CONTACTS_IDS | TASKMAN_PATCH_CONTACTS_IDS | active | `config/initializers/runtime_compat.rb:240` | taskman-maintainers | Contacts controller patch |
| HELPDESK_PROJECT_CHILDREN | TASKMAN_PATCH_HELPDESK_PROJECT_CHILDREN | active | `config/initializers/runtime_compat.rb:260` | taskman-maintainers | Project children filtering |
| RESOURCE_BOOKING_BLANK_ISSUE | TASKMAN_PATCH_RESOURCE_BOOKING_BLANK_ISSUE | active | `config/initializers/runtime_compat.rb:283` | taskman-maintainers | Blank issue filtering |
| DEAL_LINES_SUM | TASKMAN_PATCH_DEAL_LINES_SUM | active | `config/initializers/runtime_compat.rb:311` | taskman-maintainers | Deal line sums via DB |
| CONTACT_NOTES_ATTACHMENTS | TASKMAN_PATCH_CONTACT_NOTES_ATTACHMENTS | active | `config/initializers/runtime_compat.rb:346` | taskman-maintainers | Notes attachment query |
| CONTACTS_CONTROLLER_CAN | TASKMAN_PATCH_CONTACTS_CONTROLLER_CAN | active | `config/initializers/runtime_compat.rb:367` | taskman-maintainers | Contacts bulk auth flags |
| CONTACT_GROUPS_IDS | TASKMAN_PATCH_CONTACT_GROUPS_IDS | active | `config/initializers/runtime_compat.rb:393` | taskman-maintainers | Contacts visibility optimization |
| AGILE_VERSIONS_QUERY | TASKMAN_PATCH_AGILE_VERSIONS_QUERY | active | `config/initializers/runtime_compat.rb:421` | taskman-maintainers | Roadmap tracker IDs |
| AGILE_SPRINTS_QUERY | TASKMAN_PATCH_AGILE_SPRINTS_QUERY | active | `config/initializers/runtime_compat.rb:442` | taskman-maintainers | Sprint project IDs |
| TIME_ENTRY_CUSTOM_VALUES | TASKMAN_PATCH_TIME_ENTRY_CUSTOM_VALUES | active | `config/initializers/runtime_compat.rb:471` | taskman-maintainers | Custom values preload |
| TIME_ENTRY_PROJECT_MODULES | TASKMAN_PATCH_TIME_ENTRY_PROJECT_MODULES | active | `config/initializers/runtime_compat.rb:498` | taskman-maintainers | Project module preload |
| TIME_ENTRY_SUM_HOURS | TASKMAN_PATCH_TIME_ENTRY_SUM_HOURS | active | `config/initializers/runtime_compat.rb:536` | taskman-maintainers | Time sum cache |
| PROJECT_MEMBERS_PRELOAD | TASKMAN_PATCH_PROJECT_MEMBERS_PRELOAD | active | `config/initializers/runtime_compat.rb:569` | taskman-maintainers | principals_by_role preload |
| PROJECT_MEMBERS_COUNT | TASKMAN_PATCH_PROJECT_MEMBERS_COUNT | active | `config/initializers/runtime_compat.rb:614` | taskman-maintainers | member count cache hook |
| USER_ROLES_PRELOAD | TASKMAN_PATCH_USER_ROLES_PRELOAD | active | `config/initializers/runtime_compat.rb:648` | taskman-maintainers | fresh-data safe user roles |
| ACTIVITY_AUTHOR_PRELOAD | TASKMAN_PATCH_ACTIVITY_AUTHOR_PRELOAD | active | `config/initializers/runtime_compat.rb:708` | taskman-maintainers | Activity author preload for large activity streams |

## Stale / Archived Patches

| Patch | Toggle | Status | Source | Owner | Disable reason |
|---|---|---|---|---|---|
| RESOURCE_BOOKING_SUM | TASKMAN_PATCH_RESOURCE_BOOKING_SUM | stale | `config/stale/runtime_compat_disabled_patches.rb` | taskman-maintainers | slower in benchmark dataset |
| DEALS_CONTROLLER_INTERSECTION | TASKMAN_PATCH_DEALS_CONTROLLER_INTERSECTION | stale | `config/stale/runtime_compat_disabled_patches.rb` | taskman-maintainers | not helping, extra complexity |
| PROJECT_ENABLED_MODULES | TASKMAN_PATCH_PROJECT_ENABLED_MODULES | stale | `config/stale/runtime_compat_disabled_patches.rb` | taskman-maintainers | stale-read risk lane |

## Operational Verification

- Runtime state check (recommended):
  - `bundle exec rails runner performance_findings/scripts/runtime_patch_status.rb`
- Static drift audit:
  - `ruby performance_findings/scripts/audit_patches.rb`

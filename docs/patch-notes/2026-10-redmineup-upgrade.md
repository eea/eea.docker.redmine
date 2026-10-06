# RedmineUP plugin release upgrade

## Manifest and compatibility

`addons.cfg` selects the seven plugins already used by Taskman. Other archives
in the supplied `RedmineUP new` folder are not enabled. A1 remains 4.1.2.

| Plugin | Previous | New |
|---|---|---|
| Agile | 1.6.14 | 1.7.0 |
| Checklists | 4.0.2 | 4.1.0 |
| Helpdesk | 4.2.10 | 4.3.1 |
| CRM / Contacts | 4.4.7 | 4.5.0 |
| Reporter | 2.0.6 | 2.1.0 |
| Zenedit | 3.0.2 | 3.1.0 |
| Resources | 2.0.9 | 2.1.0 |

Versions were checked in the supplied archives' plugin registrations and local
changelogs. Their minimum Redmine requirements are 4.0 or 5.0 and do not exclude
Taskman's Redmine 6.1.5. This is source review, not a runtime compatibility result.
Helpdesk 4.3.1 requires Contacts >= 4.5.0. The new plugin family switches core
patch loading from include to prepend; check method precedence in real plugin
and Redmine suites. Agile, CRM, Helpdesk and Zenedit changelogs include SQL
injection fixes. Helpdesk includes mail handling and SMTP fixes.

The runtime dependency override now requires `redmineup ~> 1.1.12`, matching the
new plugin registration minimum (Zenedit requires 1.1.11). Reporter declares
`wkhtmltopdf-binary`; it is now in the image's explicit dependency list because
runtime sync removes plugin Gemfiles. No dependency download or full Bundler
resolution was possible locally.

## Patch review

- Retain the board-status query optimization: Agile 1.7.0 still joins through
  Tracker/issues/projects/versions to obtain tracker IDs.
- Correct `AGILE_ISSUES_IDS` to accept and use `scope`, retaining filters,
  pagination and order. Loaded relations/arrays use their existing rows. The old
  replacement ignored the supplied scope. A regression suite covers scoped,
  ordered/limited, empty and loaded results. CI enables this patch for testing.
- Rebase the Helpdesk sidebar on 4.3.1. Retain SQL joins for counts and distinct
  contacts, using upstream's Contact association and `text_helpdesk_contact_count`
  translation. Permissions, icons and the sidebar hook remain upstream.
- Remove `CONTACT_GROUPS_IDS`: its replacement of `Contact#visible?` ignored
  upstream public/private/author/assignee rules. CRM's own visibility methods
  now apply; the old environment toggle no longer activates a patch.
- Remove the build-time duplicate `auto_complete_taggable_tags` guard: CRM 4.5.0
  no longer declares that route (or any taggable_tags route), so the reviewed
  plugin source no longer overlaps the shared gem route.
- Keep the remaining runtime/core patches and asset materialization pending
  full runtime verification. Do not treat the current patch inventory as proof
  of an optimization: several helpers are not called by these plugin releases.
  `issue_board` takes no arguments, so AGILE_DOUBLE_COUNT delegates unchanged.
  Agile's descendants/sprint/roadmap helper replacements do not correspond to
  upstream call sites. Resource `booked_issue_ids` is absent; chart helper classes
  are namespaced and inline their filtering. Helpdesk collector/children helpers
  are not upstream call sites. CONTACT_NOTES_ATTACHMENTS targets
  `contact_attachments`, while upstream uses `notes_attachments`.
  AGILE_SPRINT_HOURS_SUM checks `@issues`, but upstream show uses a local `issues`.
  These existing ineffective optimizations were not rewired during this release.
  DEAL_LINES_SUM is conditional on the Products plugin; Products is not enabled.

## Release and deployment

Commit these changes before creating a release/tag. The tag must reference the
updated manifest and dependency list. The tag Jenkins flow delegates publishing
to `eeacms/gitflow` and skips normal test stages; run branch CI first.

Paid plugins are not embedded by default. The sync job downloads the exact
archive names from `addons.cfg`; it does not select the latest uploaded file.
Confirm the seven canonical names are available under the configured
`ADDONS_BASE_URL` plugin location, without the Reporter duplicate `(1)` suffix.
The supplied files were inspected locally; cmshare availability was not tested.

Existing addon directories can trigger an early skip based on presence alone.
For the upgrade, run the addon sync job with `ADDONS_SYNC_SKIP_IF_PRESENT=0`
and the new image/manifest. Keep backups outside `plugins/`. Back up the database,
then run the existing single migration container with `RUN_DB_MIGRATE=1`,
`RUN_PLUGIN_MIGRATE=auto`, `ASSETS_PRECOMPILE=1` and
`ASSETS_PRECOMPILE_FORCE=1` before web/jobs use the refreshed addon volume.
The Helm chart/deployment lives elsewhere; a GitHub release alone does not
refresh the production PVC. Old archives were not available locally, so the
migration delta cannot be enumerated reliably from a direct old/new comparison.

Jenkins now asserts all seven loaded plugin versions and the shared gem minimum,
so a fallback to old mounted plugins cannot silently satisfy its version check.
Check CRM public/private contact access, Agile boards/sprints and scoped IDs,
Helpdesk sidebar counts and incoming/outgoing mail, checklist editing, Reporter
PDF export, Resources charts and Zenedit WebSockets in the real deployment.

## Local validation

Archive integrity and safe extraction passed for all seven selected archives.
An isolated share-sync run with a local downloader fetched all seven exact new
archive names and the retained test theme, normalized plugin directories and
removed plugin Gemfiles. This checks the sync flow without contacting cmshare.
630 Ruby files in the extracted plugins pass syntax validation on local Ruby
3.2.3 (production uses Ruby 3.4). Changed initializer/tests and Helpdesk ERB also
pass syntax checks. An isolated test using the actual AGILE_ISSUES_IDS module
passed five cases/six assertions with scope doubles; the Rails regression tests
were added but not executed locally. Isolated Gemfile composition with the new
plugin Gemfiles and overrides passes Bundler DSL validation. Jenkins shell blocks,
Compose configuration and `git diff --check` pass.

Docker socket access is denied in this environment. Image build, bundle install,
real migrations and Rails/plugin/browser suites have not been run. These checks
remain required before rollout.

## Inspected archive SHA256 values

These record the locally supplied inputs for review; they are not yet enforced
by the downloader.

- `redmine_agile-1_7_0-pro.zip`: `f39685adb06f93bd197fc50d51ccd1f178848567a199de42d5a746c80fbc6d45`
- `redmine_checklists-4_1_0-pro.zip`: `8ae66127e7fc58d5a2170c5c7bac89d1be192d6cb52db1a1b383b98fd4c40f2e`
- `redmine_contacts_helpdesk-4_3_1-pro.zip`: `aff9a4d9b8363a0fb0009f0f5c610fface99e6a71e831774bfd59a8b45335173`
- `redmine_crm-4_5_0-pro.zip`: `5c93a9a1daab7bf4552886918b43cbcc40a526129c333e0c4655aec5585d1274`
- `redmine_reporter-2_1_0-pro.zip`: `cca3450b5691a7ffa0ff2090bee35cb1c475b7ba2aba4841b5c0dfa10ffda049`
- `redmine_zenedit-3_1_0-pro.zip`: `a6bed418cd10cac431a4c2eeb44d80bc05dbe023aef293137faeacb6d91e6674`
- `redmine_resources-2_1_0-pro.zip`: `53ba91c45470a2498b444be8d7c42fd856b3ea1784bd847b7a8fd4cd4ae562a7`

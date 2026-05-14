# Legacy Patches Notes

This document tracks legacy/ad-hoc patch artifacts that are outside the
`runtime_compat` toggle mechanism.

## Loading Model

- Legacy files are **not auto-loaded** unless explicitly required.
- Preferred runtime patch paths:
  - `config/initializers/runtime_compat.rb` (active, toggle-driven)
  - `config/stale/runtime_compat_disabled_patches.rb` (archived, not loaded)

## Lifecycle Expectations

Before adding/modifying legacy patch artifacts:

1. Decide whether behavior should be toggle-driven.
2. If yes, prefer implementation in `runtime_compat.rb` with `TASKMAN_PATCH_*` toggle.
3. Document patch status in `docs/patches/PATCHES.md`.
4. Include ownership and rollback notes.

## Current Status

- `wiki_links_controller.rb` has been moved under plugin scope:
  - `plugins/zzzz_eea_patches/app/controllers/wiki_links_controller.rb`
- New patch code should live in plugin scope or runtime toggle lanes.

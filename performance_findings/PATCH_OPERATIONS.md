# Patch Operations Guide

This guide is for maintainers/operators managing runtime patches safely.

## 1) Quick References

- Patch inventory: `docs/patches/PATCHES.md`
- Active patch code: `config/initializers/runtime_compat.rb`
- Archived patch code (not loaded): `config/stale/runtime_compat_disabled_patches.rb`
- Runtime status: `bundle exec rails runner performance_findings/scripts/runtime_patch_status.rb`
- Static drift audit: `ruby performance_findings/scripts/audit_patches.rb`

## 2) Enable a Patch (Checklist)

1. Confirm patch exists in `PATCHES.md` with `Status=active`.
2. Set `TASKMAN_PATCH_<NAME>=1` in deployment config.
3. Deploy/restart workload.
4. Verify runtime state:
   - `bundle exec rails runner performance_findings/scripts/runtime_patch_status.rb`
5. Run production-like benchmark path for affected endpoints.
6. Record outcome in change notes.

## 3) Disable a Patch (Checklist)

1. Set `TASKMAN_PATCH_<NAME>=0` (or remove env declaration if default disabled behavior is desired).
2. Deploy/restart workload.
3. Verify runtime state:
   - `bundle exec rails runner performance_findings/scripts/runtime_patch_status.rb`
4. Re-run affected endpoint checks and verify error/latency impact.
5. Update operational notes.

## 4) Rollback During Incident

Use when an active patch is suspected to cause correctness/performance incidents.

1. Identify active patch(es):
   - `bundle exec rails runner performance_findings/scripts/runtime_patch_status.rb`
2. Disable suspect patch toggle(s) in deployment env.
3. Redeploy and verify endpoint behavior.
4. Run focused regression check:
   - critical pages (`/issues`, `/projects`, `/time_entries`)
5. Log rollback reason and next action.

## 5) Restore From Stale Archive

1. Copy patch block from `config/stale/runtime_compat_disabled_patches.rb` back into `config/initializers/runtime_compat.rb`.
2. Ensure code follows current patch standards (`patch_enabled?`, `log_patch`, `to_prepare`, safe fallback).
3. Add/update entry in `docs/patches/PATCHES.md` to `Status=active`.
4. Reintroduce env toggle intentionally in deployment config if needed.
5. Validate with correctness + benchmark checks.

## 6) Drift Audit Categories

`performance_findings/scripts/audit_patches.rb` reports:

- **MISSING_DECLARATION**: Active patch toggle has no declaration in values/compose configs.
- **ORPHANED_DECLARATION**: Declared toggle does not map to active patch code.
- **STALE_REFERENCE_DECLARATION**: Declared toggle references archived/stale patch.

## 7) Before/After Operator Workflow

### Before
- Scan large initializer manually.
- Guess toggle names from comments.
- Infer runtime activation from logs.
- No clear stale restore checklist.

### After
- Read `PATCHES.md` for patch/toggle/status.
- Run `runtime_patch_status.rb` for effective runtime truth.
- Run `audit_patches.rb` for drift categories.
- Follow explicit rollback/restore checklists in this guide.

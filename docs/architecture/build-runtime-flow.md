# Build / Migrate / Runtime Flow

This repo is structured around a clear lifecycle:

1. Build image
2. Run migrations
3. Start runtime services

## 1) Build Flow

### Stage A: `base`
- Install OS dependencies.
- Install open-source plugins (`config/build/install_core_plugins.sh`).
- Optionally embed paid assets (`config/build/install_pro_assets.sh`).
- Compose `Gemfile` from base Redmine + plugin Gemfiles + documented overrides (`config/build/compose_gemfile_from_plugins.rb`).

### Stage B: `gems`
- Run `bundle install` once in a dedicated cacheable stage.

### Stage C: `runtime`
- Copy bundled gems and runtime scripts.
- Copy custom migrations from `db/migrate/`.
- Install runtime integrations (SolidQueue routes and migration glue).
- Set entrypoint to `start_redmine.sh`.

## 2) Migrate Flow

Migration container should run:
- `RUN_DB_MIGRATE=1`
- `RUN_PLUGIN_MIGRATE=auto`
- `START_SERVER=0`
- `START_CRON=0`
- `START_SOLID_QUEUE=0`

`start_redmine.sh` delegates migration phases to:
- `config/runtime/migration_runner.rb db`
- `config/runtime/migration_runner.rb plugins`

Both phases use identical retry behavior on migration lock contention.

## 3) Runtime Flow

Web/jobs containers typically run:
- `RUN_DB_MIGRATE=0`
- `RUN_PLUGIN_MIGRATE=auto`

Addon handling:
- Source of truth: `addons.cfg` (`type:name:location:archive`)
- Parser/validator: `config/lib/addons_manifest.rb`
- Runtime sync scripts in `config/runtime/`
- Shared runtime helpers: `config/runtime/common.sh`
- Migration orchestrator: `config/runtime/migration_runner.rb`

## 4) Deployment Contract (k8s parity)

| Role | Required env | Typical values | Notes |
|---|---|---|---|
| Web pod | `RUN_DB_MIGRATE`, `RUN_PLUGIN_MIGRATE`, `START_SERVER`, `START_SOLID_QUEUE`, `REQUIRE_MOUNTED_ADDONS`, `MOUNTED_ADDONS_ROOT`, `REDMINE_DB_POOL` | `0`, `auto`, `1`, `0`, `1`, `/addons/current`, `12` | Serves HTTP only; cron disabled when `CRON_IN_ASYNC_JOBS_ONLY=1`. |
| Jobs pod | `RUN_DB_MIGRATE`, `START_SERVER`, `START_SOLID_QUEUE`, `WAIT_FOR_DB_TABLES`, `REQUIRE_MOUNTED_ADDONS`, `MOUNTED_ADDONS_ROOT`, `REDMINE_DB_POOL` | `0`, `0`, `1`, `solid_queue_jobs,solid_queue_recurring_tasks`, `1`, `/addons/current`, `12` | Runs Solid Queue dispatcher/worker/scheduler. |
| Migrate pod | `RUN_DB_MIGRATE`, `RUN_PLUGIN_MIGRATE`, `START_SERVER`, `START_SOLID_QUEUE`, `REQUIRE_MOUNTED_ADDONS`, `MOUNTED_ADDONS_ROOT`, `REDMINE_DB_POOL` | `1`, `auto`, `0`, `0`, `1`, `/addons/current`, `12` | Single migration authority; runs DB then plugin migrations. |
| Addon sync pod | `ADDONS_SYNC_SOURCE`, `ADDONS_BASE_URL` or `PLUGINS_URL`, `PLUGINS_USER`, `PLUGINS_PASSWORD`, `ADDONS_VOLUME_ROOT` | `share` or `dir`, `...`, runtime secret, runtime secret, `/addons` | Syncs addons into shared PVC and applies override assets. |

Helm chart is maintained in a separate repository and should consume this contract directly.

## Redmine 6.3 Upgrade Guard

When upgrading base Redmine version:
- Keep migrate pod as single migration authority.
- Run DB migration before plugin migration (already enforced).
- Keep retry-on-lock behavior enabled.
- Validate custom migrations in `db/migrate/` still apply cleanly.
- Keep web/jobs pods with `RUN_DB_MIGRATE=0` to avoid migration races.

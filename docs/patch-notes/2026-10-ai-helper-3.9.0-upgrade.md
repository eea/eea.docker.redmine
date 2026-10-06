# AI Helper 3.5.0 → 3.9.0 upgrade

## Image and compatibility

`config/build/install_core_plugins.sh` now installs `redmine_ai_helper` from the
upstream `3.9.0` tag. The local upstream checkout was clean and matched the tag's
commit `3cd87d6cd113bbdf09a89d8aea0b4b6138fffd3b`; it was used to review the
changes from `3.5.0`. The separate plugin checkout is not changed by this upgrade.

The plugin declares Redmine `>= 6.0.0`. Its supported matrix includes
Redmine 6.1 with Ruby 3.4, matching Taskman's Redmine 6.1.5 / Ruby 3.4 / Rails 7.2.4
baseline. Upstream CI exercises Redmine `6.1-stable` with Ruby 3.2 and MySQL;
it does not establish test results for the exact Taskman combination.

Sources:

- [3.9.0 release](https://github.com/haru/redmine_ai_helper/releases/tag/3.9.0)
- [Plugin registration](https://github.com/haru/redmine_ai_helper/blob/3.9.0/init.rb)
- [Upstream CI matrix](https://github.com/haru/redmine_ai_helper/blob/3.9.0/.github/workflows/build.yml)
- [Plugin dependencies](https://github.com/haru/redmine_ai_helper/blob/3.9.0/Gemfile)

## Dependencies and patches

Between 3.5.0 and 3.9.0, `mcp` changes from `~> 0.24.0` to `~> 1.6.0` and
`websocket-client-simple`, `~> 0.9`, is added. The existing constraints on
`ruby_llm`, `ruby_llm-mcp`, `langfuse` and `qdrant-ruby` are unchanged.
The image's Gemfile composition imports these declarations automatically;
no extra gem override is needed. A real bundle resolution and image build
are still required to validate the complete dependency graph.

Keep the Taskman wiki/main-application routing patches and Banner view overrides:
AI Helper still runs inside an engine. Keep the existing test-only LLM and vector
shims pending full plugin tests; the upstream frozen-clock fix in `vector_db_test`
addresses timestamps, not the local fake analyzer's external-call behavior.
No production patch or test shim is removed in this change.

The new chat gateway remains opt-in and is not started by the existing SolidQueue
service. This upgrade does not add a gateway service or enable external chat
integrations. The existing image build precompilation/migration flow applies to
the new plugin assets and schema.

## Migrations and rollout

There are 12 new plugin migrations relative to 3.5.0. They add chat integration
tables, project scope/summary settings, log access settings and editable health
report fields, and change the model-profile temperature default.
One migration adds a unique index on `ai_helper_project_settings.project_id`.
Before migrating an existing database, check for duplicates:

```sql
SELECT project_id, COUNT(*) AS row_count
FROM ai_helper_project_settings
GROUP BY project_id
HAVING COUNT(*) > 1;
```

If there are duplicates, reconcile their settings before running the migration.
Back up the database and plugin configuration, rebuild the image, and run the
existing single migration container with `RUN_DB_MIGRATE=1`,
`RUN_PLUGIN_MIGRATE=auto` and forced asset precompilation. Start web/jobs containers
from the same rebuilt image afterward. A restart of the old image alone does not
install the new plugin or dependencies.

Mounted addon directories are authoritative at startup. If the addon volume also
contains `redmine_ai_helper`, update or remove that managed copy through the normal
addon workflow so it does not replace the image's 3.9.0 checkout with an older one.
Jenkins now verifies the loaded AI Helper version is exactly `3.9.0`, alongside
the existing Redmine/Rails/Ruby and advisory-lock checks.

After migration, review role permissions for the new health-report editing
feature. Smoke-test chat, summaries, project lists, wiki links, health reports and
MCP/vector features that are enabled in the deployment.

## Validation

In the disposable CI stack, after preparing the test DB and assets, run:

```bash
docker compose -f test/docker-compose.yml exec -T redmine bundle exec rails runner -e test \
  'puts Redmine::Plugin.find(:redmine_ai_helper).version'
docker compose -f test/docker-compose.yml exec -T redmine \
  env RAILS_ENV=test bundle exec rake redmine:plugins:ai_helper:setup_scm
docker compose -f test/docker-compose.yml exec -T redmine \
  bundle exec rake redmine:plugins:test NAME=redmine_ai_helper
docker compose -f test/docker-compose.yml exec -T redmine bundle exec rake redmine:plugins:test
docker compose -f test/docker-compose.yml exec -T redmine bundle exec rake test
docker compose -f test/docker-compose.yml exec -T redmine bundle exec rake test:system
```

Use the `ci-runtime` build target for test dependencies. The targeted suite is
also included in the existing Jenkins all-plugin test stage.
Local validation covers installer/Jenkins syntax and isolated Gemfile composition
with the actual 3.9.0 plugin Gemfile and Taskman overrides. Docker socket/network
access remains blocked in this session, so image build, bundle resolution,
database migrations and Rails/plugin/browser suites have not been run here.

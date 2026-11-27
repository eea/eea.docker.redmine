# AI Helper 3.9.0 → 3.13.1 upgrade

Delivered together with the Redmine 6.1.6 upgrade per #309624 (AI Helper errors
after plugin upgrade). This is the latest upstream release, published 2026-11-21.

## Image and compatibility

`config/build/install_core_plugins.sh` now installs `redmine_ai_helper` from the
upstream `3.13.1` tag, commit `1fe4aaa0b28a79fd8dc7a435ccfb81afffc913dd`. The
plugin declares Redmine `>= 6.0.0` in its registration at this tag, and upstream
ships Redmine 6 specific fixes in 3.13.1 (chat popup background), so the plugin
is actively maintained against the Redmine 6 line. This covers Taskman's
Redmine 6.1.6 / Ruby 3.4.13 / Rails 7.2.4 baseline; upstream CI does not
establish test results for the exact Taskman combination.

Sources:

- [3.13.1 release](https://github.com/haru/redmine_ai_helper/releases/tag/3.13.1)
- [Plugin registration at 3.13.1](https://github.com/haru/redmine_ai_helper/blob/3.13.1/init.rb)
- [Plugin Gemfile at 3.13.1](https://github.com/haru/redmine_ai_helper/blob/3.13.1/Gemfile)

## Releases in range

- **3.10.0** (2026-10-11): vector settings clarification with Qdrant/embedding
  connection tests, version CRUD tools, project hierarchy rendering fix using
  `super` for Redmine compatibility.
- **3.11.0** (2026-10-14): breaking change — migration to RubyLLM 2.1 and its
  built-in MCP client (replaces the `ruby_llm-mcp` gem); Anthropic prompt
  caching with split system prompt; web search with citations via a dedicated
  agent; chat gateway lifecycle and Slack/Discord progress/markdown rendering.
- **3.11.1** (2026-10-16): dashboard health report layout fix.
- **3.12.0** (2026-10-23): charts in project health reports, Office document
  attachments sent to the AI as Markdown, health report PDF/table style fixes,
  prompt variable replacement fix.
- **3.13.0** (2026-11-06): movable/resizable chat popup, project/member/category
  management in the AI chat, typo check and auto-completion in the issue comment
  edit form, editor controls layering fix.
- **3.13.1** (2026-11-21): chat conversation retention with some session stores,
  transparent chat popup background on Redmine 6, issue form aids after
  tracker/project/status change, LLM connection timeout detection after the
  RubyLLM 2.2 upgrade.

## Dependencies and patches

Plugin Gemfile changes relative to 3.9.0:

| Gem | 3.9.0 | 3.13.1 |
|---|---|---|
| `ruby_llm` | `~> 1.16.0` | `~> 2.2.0` |
| `ruby_llm-mcp` | `~> 1.0.0` | removed (built into RubyLLM 2.x) |
| `mcp` | `~> 1.6.0` | `~> 1.11.0` |
| `qdrant-ruby` | `~> 0.9.9` | `~> 0.9.10` |
| `langfuse` | `~> 0.1.1` | `~> 0.1.1` |
| `websocket-client-simple` | `~> 0.9` | `~> 0.9` |
| `json` | — | `< 4` (new) |

The RubyLLM 2.x migration is the significant dependency change: `ruby_llm-mcp`
drops out of the dependency graph and `ruby_llm` crosses a major version.
`config/overrides/gem_overrides.rb` pins none of these gems, so there is no
local override to adjust; the image's Gemfile composition imports the plugin
Gemfile declarations automatically. A real bundle resolution and image build
are still required to validate the complete dependency graph, and the
`redmineup ~> 1.1.12` pin is unaffected.

Keep the Taskman wiki/main-application routing patches and Banner view
overrides: AI Helper still runs inside an engine and the `ai_helper/wiki`
controller routing case is unchanged at 3.13.1. Keep the existing test-only LLM
and vector shims pending full plugin tests. The chat gateway remains opt-in and
is not started by the existing SolidQueue service; this upgrade does not add a
gateway service or enable external chat integrations.

Regarding #309624: the reported `ContextWindowExceededError` (model max
262144 tokens, prompt 262145) originates in the LiteLLM model configuration,
not in the plugin. None of the 3.10.0–3.13.1 release notes claim a fix for
prompt/context window overflow, so the LiteLLM-side max-token workaround
applied on 2026-10-14 (262144 → 4096) remains in force. Post-rollout AI chat
smoke tests are the acceptance check for #309624; if overflow recurs, the fix
is a further LiteLLM/model-side adjustment, not a plugin version.

## Migrations and rollout

Four new plugin migrations relative to 3.9.0 (tag diff of `db/migrate`, 49 → 53
files):

1. `20261008000000_remove_dimension_and_embedding_url_from_ai_helper_settings` —
   drops the unused vector settings removed in 3.10.0.
2. `20261011000000_add_prompt_caching_enabled_to_ai_helper_model_profiles` —
   Anthropic prompt caching flag.
3. `20261012000000_add_web_search_enabled_to_ai_helper_settings` — web search
   toggle.
4. `20261012000001_add_citations_to_ai_helper_messages` — citation storage for
   web search results.

These are additive/drop-column migrations without known destructive indexes.
Back up the database and plugin configuration, rebuild the image, and run the
existing single migration container with `RUN_DB_MIGRATE=1`,
`RUN_PLUGIN_MIGRATE=auto` and forced asset precompilation. Start web/jobs
containers from the same rebuilt image afterward. A restart of the old image
alone does not install the new plugin or dependencies.

Mounted addon directories are authoritative at startup. If the addon volume
also contains `redmine_ai_helper`, update or remove that managed copy through
the normal addon workflow so it does not replace the image's 3.13.1 checkout
with an older one. Jenkins now verifies the loaded AI Helper version is exactly
`3.13.1`, alongside the existing Redmine/Rails/Ruby and advisory-lock checks.

After migration, review role permissions for the new chat management actions
(project, member, category) and the typo-check/completion helpers in the issue
comment form. Smoke-test chat, summaries, project health reports with charts,
wiki links, MCP/vector features and issue form aids that are enabled in the
deployment.

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
also included in the existing Jenkins all-plugin test stage. Local validation
covers installer/Jenkins syntax and the version assertions; bundle resolution,
image build, database migrations and the Rails/plugin/browser suites run in
Jenkins CI and have not been run in this session.

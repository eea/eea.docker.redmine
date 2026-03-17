# Gem Overrides

This folder is the single place for explicit Gemfile overrides.

## How it works

At image build time, `config/build/compose_gemfile_from_plugins.rb` builds the final `Gemfile` from:

1. Redmine base `Gemfile`
2. Plugin `Gemfile` entries from `${REDMINE_PATH}/plugins/*/Gemfile`
3. Override gems declared in `config/overrides/gem_overrides.rb`

Then duplicate gem declarations are deduplicated by gem name, keeping the last declaration.
Overrides are appended last, so documented overrides win.

## Rule

Do not add ad-hoc `echo 'gem ...'` commands in Dockerfile.
If a gem must be pinned or forced, add it in `gem_overrides.rb` with a short reason comment.

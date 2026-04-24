# Documented overrides only. Keep each line justified.

# Cache client used by Redmine + plugins in this deployment.
gem 'dalli', '~> 2.7.6'
gem 'connection_pool', '~> 2.4'

# Runtime/instrumentation stack required by this image.
gem 'rack-mini-profiler', '~> 4.0'
gem 'stackprof'
gem 'mission_control-jobs'
gem 'solid_queue'
gem 'mysql2', '~> 0.5.0'
gem 'with_advisory_lock'

# RedmineUP/pro-plugin runtime dependencies must be present in image
# even when addons are synced at runtime from PVC/share.
# Track latest 1.1.x line; runtime route conflict is handled by a build-time
# compatibility patch in Dockerfile.
gem 'redmineup', '~> 1.1.5'
gem 'redmine_plugin_kit'
gem 'vcard'
gem 'wicked_pdf', '~> 1.1.0'
gem 'liquid', '~> 4.0'
gem 'acts-as-taggable-on', '~> 5.0'
gem 'tanuki_emoji'
gem 'render_async'
gem 'rss'
gem 'slim-rails'

# Ruby 4 compatibility for stdlib extraction.
gem 'ostruct'
gem 'nkf'

# Force puma availability in final image.
gem 'puma'

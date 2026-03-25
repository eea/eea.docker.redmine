# Documented overrides only. Keep each line justified.

# Cache client used by Redmine + plugins in this deployment.
gem 'dalli', '~> 2.7.6'

# Runtime/instrumentation stack required by this image.
gem 'rails_pulse'
gem 'mission_control-jobs'
gem 'solid_queue'
gem 'mysql2', '~> 0.5.0'

# RedmineUP/pro-plugin runtime dependencies must be present in image
# even when addons are synced at runtime from PVC/share.
gem 'redmineup'
gem 'redmine_plugin_kit'
gem 'vcard'
gem 'wicked_pdf', '~> 1.1.0'
gem 'liquid', '~> 4.0'
gem 'acts-as-taggable-on', '~> 5.0'
gem 'tanuki_emoji'
gem 'render_async'
gem 'rss'
gem 'slim-rails'

# Ruby 3.4 compatibility for stdlib extraction.
gem 'ostruct'

# Force puma availability in final image.
gem 'puma'

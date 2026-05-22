# config/initializers/rack_mini_profiler.rb
#
# FALLBACK initializer for Rack::MiniProfiler authorization.
# PRIMARY configuration is done by plugins/zzzz_eea_patches/lib/mini_profiler_patch.rb.
# This file only activates when the plugin's MiniProfilerPatch module is NOT present.
#
# If the plugin is present, this file exits early (line 12 below) to avoid
# double-configuration or override conflicts.

enabled = ENV.fetch("RACK_MINI_PROFILER_ENABLED", "0") == "1"

begin
  require "rack-mini-profiler"
rescue LoadError
  nil
end

return unless defined?(Rack::MiniProfiler)

# --- Plugin takes precedence: skip if zzzz_eea_patches handles it ---
return if defined?(EeaPatches::MiniProfilerPatch)

apply_config = lambda do
  Rack::MiniProfiler.config.enabled = enabled if Rack::MiniProfiler.config.respond_to?(:enabled=)
  Rack::MiniProfiler.config.auto_inject = enabled
  Rack::MiniProfiler.config.authorization_mode = :allow_authorized
  Rack::MiniProfiler.config.base_url_path = "/mini-profiler-resources/" if Rack::MiniProfiler.config.respond_to?(:base_url_path=)
  if Rack::MiniProfiler.config.respond_to?(:enable_hotwire_turbo_drive_support=)
    Rack::MiniProfiler.config.enable_hotwire_turbo_drive_support = true
  end
  # Admin-only fallback (NOT allow_all)
  Rack::MiniProfiler.config.pre_authorize_cb = lambda do |*|
    defined?(User) && User.current&.admin?
  end
  Rack::MiniProfiler.config.user_provider = lambda do |*|
    user = User.current
    user&.logged? ? user.login : "anonymous"
  end
end

apply_config.call

if defined?(Rails) && Rails.respond_to?(:application)
  Rails.application.config.after_initialize do
    apply_config.call unless defined?(EeaPatches::MiniProfilerPatch)
  end
end

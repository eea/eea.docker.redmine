enabled = ENV.fetch("RACK_MINI_PROFILER_ENABLED", "0") == "1"

begin
  require "rack-mini-profiler"
rescue LoadError
  nil
end

return unless defined?(Rack::MiniProfiler)

apply_config = lambda do
  Rack::MiniProfiler.config.enabled = enabled if Rack::MiniProfiler.config.respond_to?(:enabled=)
  Rack::MiniProfiler.config.auto_inject = enabled
  Rack::MiniProfiler.config.base_url_path = "/mini-profiler-resources/" if Rack::MiniProfiler.config.respond_to?(:base_url_path=)
  if Rack::MiniProfiler.config.respond_to?(:enable_hotwire_turbo_drive_support=)
    Rack::MiniProfiler.config.enable_hotwire_turbo_drive_support = true
  end
end

apply_config.call

if defined?(Rails) && Rails.respond_to?(:application)
  Rails.application.config.after_initialize do
    apply_config.call
    Rack::MiniProfiler.config.authorization_mode = :allow_all
  end
end

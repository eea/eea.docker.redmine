enabled = ENV.fetch("RACK_MINI_PROFILER_ENABLED", "0") == "1"
MINI_PROFILER_SESSION_KEY = :mini_profiler_enabled unless defined?(MINI_PROFILER_SESSION_KEY)

begin
  require "rack-mini-profiler"
rescue LoadError
  nil
end

return unless defined?(Rack::MiniProfiler)

profiler_authorized = lambda do |env|
  begin
    request = ActionDispatch::Request.new(env)

    # Always allow access to MiniProfiler static resources.
    base_path = Rack::MiniProfiler.config.base_url_path.to_s
    if base_path != "" && request.path.to_s.start_with?(base_path)
      return true
    end

    session = request.session

    # Admin-only runtime toggle via URL for current session:
    #   ?miniprofiler=on  -> enable profiling
    #   ?miniprofiler=off -> disable profiling
    toggle = request.params["miniprofiler"].to_s.downcase
    if toggle == "on"
      session[MINI_PROFILER_SESSION_KEY] = true
    elsif toggle == "off"
      session.delete(MINI_PROFILER_SESSION_KEY)
    end

    allow_all = ENV.fetch("RACK_MINI_PROFILER_ALLOW_ALL", "0") == "1"
    user_id = session && session[:user_id]
    user = defined?(User) ? User.find_by(id: user_id) : nil
    allowed = allow_all || (user&.admin? && session[MINI_PROFILER_SESSION_KEY] == true)

    Rack::MiniProfiler.authorize_request if allowed
    allowed
  rescue StandardError
    false
  end
end

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

    # Use :allow_authorized so pre_authorize_cb gates the profiler.
    # With RACK_MINI_PROFILER_ALLOW_ALL=1, all requests are authorized.
    Rack::MiniProfiler.config.authorization_mode = :allow_authorized
    Rack::MiniProfiler.config.pre_authorize_cb = profiler_authorized
  end
end

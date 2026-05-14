enabled = ENV.fetch("RACK_MINI_PROFILER_ENABLED", "0") == "1"
session_toggle_key = :mini_profiler_enabled

return unless defined?(Rack::MiniProfiler)

profiler_authorized = lambda do |env|
  begin
    request = ActionDispatch::Request.new(env)
    session = request.session

    # Admin-only runtime toggle via URL for current session:
    #   ?miniprofiler=on  -> enable profiling
    #   ?miniprofiler=off -> disable profiling
    toggle = request.params["miniprofiler"].to_s.downcase
    if toggle == "on"
      session[session_toggle_key] = true
    elsif toggle == "off"
      session.delete(session_toggle_key)
    end

    # Escape hatch for ops when explicitly requested
    return true if ENV.fetch("RACK_MINI_PROFILER_ALLOW_ALL", "0") == "1"

    user_id = session && session[:user_id]
    user = defined?(User) ? User.find_by(id: user_id) : nil
    user&.admin? && session[session_toggle_key] == true
  rescue StandardError
    false
  end
end

apply_config = lambda do
  Rack::MiniProfiler.config.auto_inject = enabled
  Rack::MiniProfiler.config.authorization_mode = :allow_authorized
  if Rack::MiniProfiler.config.respond_to?(:enable_hotwire_turbo_drive_support=)
    Rack::MiniProfiler.config.enable_hotwire_turbo_drive_support = true
  end

  if enabled
    Rack::MiniProfiler.config.pre_authorize_cb = profiler_authorized
  else
    Rack::MiniProfiler.config.pre_authorize_cb = ->(_env) { false }
  end
end

apply_config.call
Rails.application.config.after_initialize { apply_config.call } if defined?(Rails) && Rails.respond_to?(:application)

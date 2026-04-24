enabled = ENV.fetch("RACK_MINI_PROFILER_ENABLED", "0") == "1"

return unless defined?(Rack::MiniProfiler)

profiler_authorized = lambda do |env|
  begin
    return true if ENV.fetch("RACK_MINI_PROFILER_ALLOW_ALL", "0") == "1"

    request = ActionDispatch::Request.new(env)
    session = request.session
    user_id = session && session[:user_id]
    user = defined?(User) ? User.find_by(id: user_id) : nil
    user&.admin? || false
  rescue StandardError
    false
  end
end

apply_config = lambda do
  Rack::MiniProfiler.config.auto_inject = enabled
  if Rack::MiniProfiler.config.respond_to?(:enable_hotwire_turbo_drive_support=)
    Rack::MiniProfiler.config.enable_hotwire_turbo_drive_support = true
  end

  if enabled
    Rack::MiniProfiler.config.authorization_mode = :allow_all
    Rack::MiniProfiler.config.pre_authorize_cb = profiler_authorized
  else
    Rack::MiniProfiler.config.pre_authorize_cb = ->(_env) { false }
  end
end

apply_config.call
Rails.application.config.after_initialize { apply_config.call } if defined?(Rails) && Rails.respond_to?(:application)

enabled = ENV.fetch("RACK_MINI_PROFILER_ENABLED", "0") == "1"
MINI_PROFILER_SESSION_KEY = :mini_profiler_enabled unless defined?(MINI_PROFILER_SESSION_KEY)

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

# In production allow_authorized mode, Rack::MiniProfiler.authorize_request
# must be called during a controller request. We keep a session toggle driven by
# ?miniprofiler=on|off and only authorize admin sessions.
if defined?(Rails) && Rails.respond_to?(:application)
  Rails.application.config.to_prepare do
    next unless enabled
    next unless defined?(ApplicationController)

    unless defined?(TaskmanMiniProfilerAuthorization)
      module TaskmanMiniProfilerAuthorization
        def self.included(base)
          base.before_action :taskman_mini_profiler_authorize_request
        end

        private

        def taskman_mini_profiler_authorize_request
          toggle = params[:miniprofiler].to_s.downcase
          if toggle == "on"
            session[MINI_PROFILER_SESSION_KEY] = true
          elsif toggle == "off"
            session.delete(MINI_PROFILER_SESSION_KEY)
          end

          return unless session[MINI_PROFILER_SESSION_KEY] == true

          allow_all = ENV.fetch("RACK_MINI_PROFILER_ALLOW_ALL", "0") == "1"
          uid = session && session[:user_id]
          is_admin = defined?(User) ? (User.find_by(id: uid)&.admin? || false) : false

          return unless allow_all || is_admin

          Rack::MiniProfiler.authorize_request
        rescue StandardError
          nil
        end
      end
    end

    ApplicationController.include(TaskmanMiniProfilerAuthorization) unless ApplicationController.ancestors.include?(TaskmanMiniProfilerAuthorization)
  end
end

apply_config.call
Rails.application.config.after_initialize { apply_config.call } if defined?(Rails) && Rails.respond_to?(:application)

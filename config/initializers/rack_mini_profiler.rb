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
  # Skip profiling entirely for non-admins (zero data collection)
  Rack::MiniProfiler.config.pre_authorize_cb = lambda { |env|
    req = ActionDispatch::Request.new(env)
    # Allow resource serving for admin access
    return false if req.path.start_with?(Rack::MiniProfiler.config.base_url_path)
    # Only admin users may profile
    user = defined?(User) ? User.current : nil
    user && user.admin?
  }
  # Prevent storage failures from anonymous user_provider
  Rack::MiniProfiler.config.user_provider = -> { "anonymous" }
end

apply_config.call

if defined?(Rails) && Rails.respond_to?(:application)
  Rails.application.config.after_initialize do
    apply_config.call

    # Admins: profiling controlled by ?miniprofiler=on/off.
    # OFF by default — must explicitly enable via query param.
    ApplicationController.class_eval do
      before_action :admin_profiler_toggle

      def admin_profiler_toggle
        return unless defined?(User) && User.current&.admin?
        return if request.path.start_with?(Rack::MiniProfiler.config.base_url_path)

        toggle = request.params["miniprofiler"].to_s.downcase
        if toggle == "on"
          session[:mini_profiler_enabled] = true
        elsif toggle == "off"
          session[:mini_profiler_enabled] = false
        end
      end
    end

    # Admins: only inject script if session is enabled
    ApplicationController.class_eval do
      before_action :check_admin_profiler_enabled

      def check_admin_profiler_enabled
        return unless defined?(User) && User.current&.admin?
        return if request.path.start_with?(Rack::MiniProfiler.config.base_url_path)

        # If admin profiling is explicitly disabled for this session,
        # cancel injection
        Rack::MiniProfiler.current&.inject_js = false if session[:mini_profiler_enabled] != true
      end
    end
  end
end

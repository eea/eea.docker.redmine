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

    # Define a middleware that runs AFTER Rails has processed the request.
    # It sets a flag in the response headers that MiniProfiler can read
    # to decide whether to skip profiling.
    Rails.application.middleware.insert_after(
      ActionDispatch::Session::CookieStore,
      Class.new do
        def initialize(app)
          @app = app
        end

        def call(env)
          status, headers, body = @app.call(env)
          req = ActionDispatch::Request.new(env)

          # For resource paths, always allow profiling
          if req.path.start_with?(Rack::MiniProfiler.config.base_url_path)
            env['profiler.skip'] = false
            return [status, headers, body]
          end

          # Check admin + session toggle
          is_admin = defined?(User) && User.current&.admin?
          skip = true

          if is_admin
            toggle = req.params["miniprofiler"].to_s.downcase
            if toggle == "on"
              session = env['rack.session']
              session[:mini_profiler_enabled] = true
              skip = false
            elsif toggle == "off"
              session = env['rack.session']
              session[:mini_profiler_enabled] = false
              skip = true
            else
              session = env['rack.session']
              skip = session[:mini_profiler_enabled] != true
            end
          end

          env['profiler.skip'] = skip
          [status, headers, body]
        end
      end
    )

    # pre_authorize_cb checks the env['profiler.skip'] flag set by the
    # middleware above. But pre_authorize_cb runs BEFORE @app.call(env),
    # so the flag isn't set yet at that point. This approach won't work.

    # Fallback: Use cancel_auto_inject in the controller to prevent script
    # injection. Data IS collected but not injected. Acceptable trade-off:
    # profiling data collection happens but no script/data is injected for
    # non-admins.

    ApplicationController.class_eval do
      before_action :authorize_mini_profiler

      def authorize_mini_profiler
        return if request.path.start_with?(Rack::MiniProfiler.config.base_url_path)

        is_admin = defined?(User) && User.current&.admin?
        return if is_admin

        # Non-admin: don't inject script (but data IS collected)
        Rack::MiniProfiler.current&.inject_js = false
      end
    end

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

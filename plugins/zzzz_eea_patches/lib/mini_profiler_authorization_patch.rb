module EeaPatches
  module MiniProfilerAuthorizationPatch
    def self.apply!
      return unless defined?(::ApplicationController)
      return if ::ApplicationController < ControllerMethods

      ::ApplicationController.include(ControllerMethods)
      ::ApplicationController.after_action :authorize_mini_profiler_for_current_user
    end

    module ControllerMethods
      private

      def authorize_mini_profiler_for_current_user
        return unless defined?(Rack::MiniProfiler)

        # Toggle profiler via ?miniprofiler=on / ?miniprofiler=off query param.
        # Setting is persisted in session so it stays across page navigations.
        case params[:miniprofiler]
        when 'on'
          session[:miniprofiler] = true
        when 'off'
          session[:miniprofiler] = false
        end

        # Only authorize if session toggle is on AND user is authorized (admin etc.)
        return unless session[:miniprofiler]
        return unless EeaPatches::MiniProfilerPatch.check_profiler_access?

        Rack::MiniProfiler.authorize_request
      end
    end
  end
end

# Zeitwerk expects top-level MiniProfilerAuthorizationPatch for this file path.
MiniProfilerAuthorizationPatch = EeaPatches::MiniProfilerAuthorizationPatch unless defined?(::MiniProfilerAuthorizationPatch)

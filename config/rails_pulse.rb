RailsPulse.configure do |config|
  config.enabled = ENV.fetch("RAILS_PULSE_ENABLED", "1") == "1"
  config.mount_path = "/rails_pulse"
  config.ignored_routes = (config.ignored_routes || []) + [
    "/up",
    "/healthz",
    "/readyz",
    "/livez",
    %r{\A/errors/static_errors/containers\.gif\z}
  ]

  auth_enabled_default = "1"
  config.authentication_enabled = ENV.fetch("RAILS_PULSE_AUTH_ENABLED", auth_enabled_default) == "1"
  config.authentication_redirect_path = "/login"

  auth_mode = ENV.fetch("RAILS_PULSE_AUTH_MODE", "basic")

  # HTTP basic auth can be enabled for external operators.
  # Fallback mode keeps existing Redmine session-based admin auth.
  config.authentication_method = proc do
    if auth_mode == "basic"
      expected_user = ENV.fetch("RAILS_PULSE_BASIC_AUTH_USERNAME", "").presence ||
        ENV.fetch("MISSION_CONTROL_JOBS_BASIC_AUTH_USERNAME", "admin")
      expected_pass = ENV.fetch("RAILS_PULSE_BASIC_AUTH_PASSWORD", "").presence ||
        ENV.fetch("MISSION_CONTROL_JOBS_BASIC_AUTH_PASSWORD", ENV.fetch("ADMIN_BOOTSTRAP_PASSWORD", ""))

      if expected_user.empty? || expected_pass.empty?
        render plain: "Rails Pulse auth credentials are not configured", status: :service_unavailable
        next
      end

      authenticated = authenticate_with_http_basic do |username, password|
        ActiveSupport::SecurityUtils.secure_compare(username.to_s, expected_user) &&
          ActiveSupport::SecurityUtils.secure_compare(password.to_s, expected_pass)
      end

      request_http_basic_authentication("Rails Pulse") unless authenticated
      next
    end

    user = nil

    if defined?(User) && respond_to?(:session, true)
      uid = session[:user_id]
      user = User.find_by(id: uid) if uid
    end

    user ||= (defined?(User) ? User.current : nil)

    unless user&.logged?
      redirect_to "/login"
      next
    end

    next if user.admin?

    render plain: "Forbidden", status: :forbidden
  end
end

# rails_pulse 0.2.4 can raise RecordNotFound/RecordNotUnique during
# Query association under concurrency. Make association idempotent.
Rails.application.config.to_prepare do
  if defined?(RailsPulse::Middleware::RequestCollector)
    unless defined?(RailsPulseKubeProbeFilter)
      module RailsPulseKubeProbeFilter
        private

        def should_ignore_route?(req)
          user_agent = req.user_agent.to_s.downcase
          return true if user_agent.include?("kube-probe")

          super
        end
      end
    end

    collector = RailsPulse::Middleware::RequestCollector
    unless collector.ancestors.include?(RailsPulseKubeProbeFilter)
      collector.prepend(RailsPulseKubeProbeFilter)
    end
  end

  next unless defined?(RailsPulse::Operation) && defined?(RailsPulse::Query)

  RailsPulse::Operation.class_eval do
    private

    def associate_query
      return unless operation_type == "sql" && label.present?

      normalized = normalize_query_label(label)
      return if normalized.blank?

      query = RailsPulse::Query.find_by(normalized_sql: normalized)
      unless query
        begin
          query = RailsPulse::Query.create!(normalized_sql: normalized)
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
          query = RailsPulse::Query.find_by(normalized_sql: normalized)
        end
      end

      self.query = query if query
    rescue StandardError => e
      Rails.logger.warn("[RailsPulse] associate_query fallback: #{e.class}: #{e.message}")
    end
  end
end

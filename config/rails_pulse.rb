RailsPulse.configure do |config|
  config.enabled = ENV.fetch("RAILS_PULSE_ENABLED", "1") == "1"

  auth_enabled_default = "0"
  config.authentication_enabled = ENV.fetch("RAILS_PULSE_AUTH_ENABLED", auth_enabled_default) == "1"
  config.authentication_redirect_path = "/login"

  # Reuse Redmine session auth instead of HTTP basic auth prompts.
  config.authentication_method = proc do
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

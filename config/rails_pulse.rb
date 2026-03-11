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

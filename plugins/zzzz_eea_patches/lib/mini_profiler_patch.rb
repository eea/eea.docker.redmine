# plugins/zzzz_eea_patches/lib/mini_profiler_patch.rb
#
# Per-request authorization for Rack::MiniProfiler.
# Only admin users (and optionally specific users/groups) see the profiler overlay.
#
# Config via ENV vars (set in K8s deployment):
#   RACK_MINI_PROFILER_ENABLED      - "1" to enable, "0" to disable (default "0")
#   RACK_MINI_PROFILER_ALLOW_ADMIN  - "1" to allow admin users (default "1")
#   RACK_MINI_PROFILER_ALLOW_USERS  - comma-separated login names, e.g. "alice,bob"
#   RACK_MINI_PROFILER_ALLOW_GROUPS - comma-separated numeric group IDs
#
# IMPORTANT: This plugin MUST load before config/initializers/rack_mini_profiler.rb
# to take precedence. The initializer checks for this module and skips if present.

module EeaPatches
  module MiniProfilerPatch
    # Called once at plugin load time to wire MiniProfiler authorization.
    def self.configure!
      return unless defined?(Rack::MiniProfiler)

      enabled = ENV.fetch("RACK_MINI_PROFILER_ENABLED", "0") == "1"
      return unless enabled

      Rack::MiniProfiler.config.enabled = true
      Rack::MiniProfiler.config.auto_inject = true
      Rack::MiniProfiler.config.authorization_mode = :allow_authorized
      Rack::MiniProfiler.config.base_url_path = "/mini-profiler-resources/"

      if Rack::MiniProfiler.config.respond_to?(:enable_hotwire_turbo_drive_support=)
        Rack::MiniProfiler.config.enable_hotwire_turbo_drive_support = true
      end

      # CRITICAL: pre_authorize_cb MUST return true always.
      # It runs at MIDDLEWARE time, BEFORE the controller sets User.current.
      # User.current is nil at this point, so any User-based check here
      # would silently return false for ALL requests — disabling profiling.
      # Authorization is enforced by after_action (authorization_patch.rb)
      # which calls Rack::MiniProfiler.authorize_request only for authorized
      # users. This integrates with :allow_authorized mode correctly:
      #   1st authorized req: after_action sets mp_authorized → cookie set
      #   2nd authorized req: valid cookie → profiling + overlay injection
      Rack::MiniProfiler.config.pre_authorize_cb = lambda { |*| true }

      # user_provider: returns a string identity for profiler storage/metadata.
      # Must NOT return nil to avoid storage errors.
      Rack::MiniProfiler.config.user_provider = lambda do |*|
        user = User.current
        user&.logged? ? user.login : "anonymous"
      end

      Rails.logger.info(
        "[MiniProfiler] Enabled (mode=:allow_authorized, " \
        "admin_allowed=#{ENV.fetch('RACK_MINI_PROFILER_ALLOW_ADMIN', '1')}, " \
        "users=#{ENV.fetch('RACK_MINI_PROFILER_ALLOW_USERS', '')}, " \
        "groups=#{ENV.fetch('RACK_MINI_PROFILER_ALLOW_GROUPS', '')})"
      )
    end

    # Returns true if the current Redmine user is authorized to see profiler.
    # Called per-request inside the after_action hook (authorization_patch.rb),
    # at which point User.current is properly set by the controller.
    def self.check_profiler_access?
      return false unless defined?(User) && defined?(User.current)

      user = User.current
      return false unless user&.logged?
      return false if user.anonymous?

      # 1. Admin users always allowed (when feature enabled)
      allow_admin = ENV.fetch("RACK_MINI_PROFILER_ALLOW_ADMIN", "1") == "1"
      return true if allow_admin && user.admin?

      # 2. Specific users by login name
      allowed_logins = allowed_logins_from_env
      return true if allowed_logins.include?(user.login)

      # 3. Group membership
      allowed_group_ids = allowed_group_ids_from_env
      return true if allowed_group_ids.any? { |gid| user.groups.pluck(:id).include?(gid) }

      # Default deny
      false
    end

    private

    def self.allowed_logins_from_env
      @allowed_logins_cache ||= begin
        ENV.fetch("RACK_MINI_PROFILER_ALLOW_USERS", "").split(",").map(&:strip).compact
      end
    end

    def self.allowed_group_ids_from_env
      @allowed_group_ids_cache ||= begin
        ENV.fetch("RACK_MINI_PROFILER_ALLOW_GROUPS", "").split(",").map(&:strip).compact.map(&:to_i)
      end
    end
  end
end

# Zeitwerk expects top-level MiniProfilerPatch for this file path.
# Alias to namespaced implementation to avoid eager-load NameError.
MiniProfilerPatch = EeaPatches::MiniProfilerPatch unless defined?(::MiniProfilerPatch)

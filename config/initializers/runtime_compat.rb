require "active_support/core_ext/string/inflections"

# Redmine 6 nested-set locking expects a class-level advisory lock helper.
# Some runtime bundles miss that extension; provide a safe fallback.
unless ActiveRecord::Base.respond_to?(:with_advisory_lock!)
  class << ActiveRecord::Base
    def with_advisory_lock!(_lock_name = nil, **_options)
      return yield if block_given?
      true
    end
  end
end

# redmine_banner 0.3.x may try to generate this legacy route directly:
# controller: "ai_helper/global_banner", action: "show", id: "<project>"
# Add a shim route when missing so banner rendering does not crash.
Rails.application.config.to_prepare do
  has_global_banner_route = Rails.application.routes.routes.any? do |route|
    route.defaults[:controller] == "ai_helper/global_banner" &&
      route.defaults[:action] == "show"
  end

  next if has_global_banner_route

  Rails.application.routes.append do
    get "ai_helper/global_banner/:id",
      to: "ai_helper/global_banner#show",
      as: :ai_helper_global_banner_legacy
  end
end

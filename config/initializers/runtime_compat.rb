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

# redmine_agile board status lookup can generate a very expensive join
# across trackers/issues/projects/versions on large datasets.
# Reuse the filtered issue scope to fetch only distinct tracker ids.
Rails.application.config.to_prepare do
  next unless defined?(AgileQuery)

  unless defined?(TaskmanAgileQueryPerfPatch)
    module TaskmanAgileQueryPerfPatch
      def board_issue_statuses
        return @board_issue_statuses if defined?(@board_issue_statuses) && @board_issue_statuses

        tracker_ids =
          issue_scope
          .unscope(:select, :order)
          .where.not("#{Issue.table_name}.tracker_id" => nil)
          .distinct
          .pluck("#{Issue.table_name}.tracker_id")

        status_ids =
          if tracker_ids.any?
            WorkflowTransition.where(tracker_id: tracker_ids).distinct.pluck(:old_status_id, :new_status_id).flatten.uniq
          else
            []
          end

        @board_issue_statuses = IssueStatus.where(id: status_ids)
      rescue StandardError => e
        Rails.logger.warn("[AgileQueryPerfPatch] board_issue_statuses fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  AgileQuery.prepend(TaskmanAgileQueryPerfPatch) unless AgileQuery.ancestors.include?(TaskmanAgileQueryPerfPatch)
end

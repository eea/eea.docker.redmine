require 'active_support/core_ext/string/inflections'

module TaskmanRuntimeCompat
  module_function

  # Toggle per patch:
  # TASKMAN_PATCH_<NAME>=0 to disable (accepted: 0,false,no,off)
  def patch_enabled?(name, default: false)
    raw = ENV.fetch("TASKMAN_PATCH_#{name}", default ? '1' : '0').to_s.strip.downcase
    !%w[0 false no off].include?(raw)
  end

  # Boot-time visibility so we can correlate enabled patches with latency/error.
  def log_patch(name, enabled)
    if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
      Rails.logger.info("[runtime_compat] patch=#{name} enabled=#{enabled}")
    end
  rescue StandardError
    nil
  end
end

# redmine_agile board status lookup - query rewrite avoids expensive join
# Original: joins issue_scope through tracker/project to workflows
# Fixed: fetches tracker_ids first, then queries workflows directly
# Toggle: TASKMAN_PATCH_AGILE_QUERY
agile_query_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('AGILE_QUERY')
TaskmanRuntimeCompat.log_patch('AGILE_QUERY', agile_query_patch_enabled)
Rails.application.config.to_prepare do
  next unless agile_query_patch_enabled
  next unless defined?(AgileQuery)

  unless defined?(TaskmanAgileQueryPerfPatch)
    module TaskmanAgileQueryPerfPatch
      def board_issue_statuses
        tracker_ids = issue_scope.unscope(:select, :order)
                               .where.not("#{Issue.table_name}.tracker_id" => nil)
                               .distinct
                               .pluck("#{Issue.table_name}.tracker_id")

        return IssueStatus.none if tracker_ids.empty?

        status_ids = WorkflowTransition.where(tracker_id: tracker_ids)
                                       .distinct
                                       .pluck(:old_status_id, :new_status_id)
                                       .flatten
                                       .uniq

        IssueStatus.where(id: status_ids)
      rescue StandardError => e
        Rails.logger.warn("[AgileQueryPerfPatch] board_issue_statuses fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

AgileQuery.prepend(TaskmanAgileQueryPerfPatch) unless AgileQuery.ancestors.include?(TaskmanAgileQueryPerfPatch)
end

# redmine_agile issues_ids - pluck IDs instead of loading full AR objects
# Original: issue_scope.map(&:id)
# Fixed: issue_scope.pluck(:id)
# Toggle: TASKMAN_PATCH_AGILE_ISSUES_IDS
agile_issues_ids_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('AGILE_ISSUES_IDS')
TaskmanRuntimeCompat.log_patch('AGILE_ISSUES_IDS', agile_issues_ids_patch_enabled)
Rails.application.config.to_prepare do
  next unless agile_issues_ids_patch_enabled
  next unless defined?(AgileQuery)

  unless defined?(TaskmanAgileIssuesIdsPatch)
    module TaskmanAgileIssuesIdsPatch
      def issues_ids
        @issues_ids ||= issue_scope.unscope(:select, :order).pluck(:id)
      rescue StandardError => e
        Rails.logger.warn("[AgileIssuesIdsPatch] issues_ids fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  AgileQuery.prepend(TaskmanAgileIssuesIdsPatch) unless AgileQuery.ancestors.include?(TaskmanAgileIssuesIdsPatch)
end

# redmine_resources ResourceBookingQuery booked_issue_ids - pluck issue IDs
# Original: approved_bookings.map(&:issue_id)
# Fixed: approved_bookings.pluck(:issue_id)
# Toggle: TASKMAN_PATCH_RESOURCE_BOOKING_QUERY
resource_booking_query_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('RESOURCE_BOOKING_QUERY')
TaskmanRuntimeCompat.log_patch('RESOURCE_BOOKING_QUERY', resource_booking_query_patch_enabled)
Rails.application.config.to_prepare do
  next unless resource_booking_query_patch_enabled
  next unless defined?(ResourceBookingQuery)

  unless defined?(TaskmanResourceBookingQueryPatch)
    module TaskmanResourceBookingQueryPatch
      def booked_issue_ids
        approved_bookings.pluck(:issue_id)
      rescue StandardError => e
        Rails.logger.warn("[ResourceBookingQueryPatch] booked_issue_ids fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  ResourceBookingQuery.prepend(TaskmanResourceBookingQueryPatch) unless ResourceBookingQuery.ancestors.include?(TaskmanResourceBookingQueryPatch)
end

# redmine_resources ResourceBooking total_hours_sum - DB aggregation instead of Ruby sum
# Original: to_a.sum(&:total_hours)
# Fixed: sum(:total_hours)
# Toggle: TASKMAN_PATCH_RESOURCE_BOOKING_SUM
resource_booking_sum_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('RESOURCE_BOOKING_SUM')
TaskmanRuntimeCompat.log_patch('RESOURCE_BOOKING_SUM', resource_booking_sum_patch_enabled)
Rails.application.config.to_prepare do
  next unless resource_booking_sum_patch_enabled
  next unless defined?(ResourceBooking)

  unless defined?(TaskmanResourceBookingSumPatch)
    module TaskmanResourceBookingSumPatch
      def total_hours_sum
        sum(:total_hours)
      rescue StandardError => e
        Rails.logger.warn("[ResourceBookingSumPatch] total_hours_sum fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

ResourceBooking.prepend(TaskmanResourceBookingSumPatch) unless ResourceBooking.ancestors.include?(TaskmanResourceBookingSumPatch)
end

# redmine_agile issue_board - avoid double COUNT/SELECT by limit+1 fetch
# Original: separate count query before data fetch
# Fixed: fetch limit+1 rows and trim in Ruby
# Toggle: TASKMAN_PATCH_AGILE_DOUBLE_COUNT
agile_double_count_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('AGILE_DOUBLE_COUNT')
TaskmanRuntimeCompat.log_patch('AGILE_DOUBLE_COUNT', agile_double_count_patch_enabled)
Rails.application.config.to_prepare do
  next unless agile_double_count_patch_enabled
  next unless defined?(AgileQuery)

  unless defined?(TaskmanAgileDoubleCountPatch)
    module TaskmanAgileDoubleCountPatch
      def issue_board(options = {})
        limit = options[:limit] || per_page_option
        result = super(options.merge(limit: limit + 1))
        if result.respond_to?(:size) && result.size > limit
          result = result.first(limit)
        end
        result
      rescue StandardError => e
        Rails.logger.warn("[AgileDoubleCountPatch] issue_board fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  AgileQuery.prepend(TaskmanAgileDoubleCountPatch) unless AgileQuery.ancestors.include?(TaskmanAgileDoubleCountPatch)
end

# redmine_agile descendants filter - SQL JOIN instead of Ruby select/map
# Original: descendants.select { |sub| sub.module_enabled?('agile') }.map(&:id)
# Fixed: JOIN enabled_modules and pluck ids
# Toggle: TASKMAN_PATCH_AGILE_DESCENDANTS_JOIN
agile_descendants_join_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('AGILE_DESCENDANTS_JOIN')
TaskmanRuntimeCompat.log_patch('AGILE_DESCENDANTS_JOIN', agile_descendants_join_patch_enabled)
Rails.application.config.to_prepare do
  next unless agile_descendants_join_patch_enabled
  next unless defined?(AgileQuery)

  unless defined?(TaskmanAgileDescendantsJoinPatch)
    module TaskmanAgileDescendantsJoinPatch
      def agile_subproject_ids(project)
        project.descendants
               .joins(:enabled_modules)
               .where(enabled_modules: { name: 'agile' })
               .pluck(:id)
      rescue StandardError => e
        Rails.logger.warn("[AgileDescendantsJoinPatch] agile_subproject_ids fallback: #{e.class}: #{e.message}")
        project.descendants.select { |sub| sub.module_enabled?('agile') }.map(&:id)
      end
    end
  end

  AgileQuery.prepend(TaskmanAgileDescendantsJoinPatch) unless AgileQuery.ancestors.include?(TaskmanAgileDescendantsJoinPatch)
end

# redmine_agile shared sprint projects - collapse nested map chain
# Original: shared_agile_sprints.map(&:shared_projects)...flatten.uniq
# Fixed: JOIN shared_projects and pluck project ids in SQL
# Toggle: TASKMAN_PATCH_AGILE_SPRINT_PROJECTS
agile_sprint_projects_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('AGILE_SPRINT_PROJECTS')
TaskmanRuntimeCompat.log_patch('AGILE_SPRINT_PROJECTS', agile_sprint_projects_patch_enabled)
Rails.application.config.to_prepare do
  next unless agile_sprint_projects_patch_enabled
  next unless defined?(AgileQuery) && defined?(AgileSprint)

  unless defined?(TaskmanAgileSprintProjectsPatch)
    module TaskmanAgileSprintProjectsPatch
      def shared_sprint_project_ids(project)
        AgileSprint.joins(:shared_projects)
                   .where(agile_sprints: { id: project.shared_agile_sprints.pluck(:id) })
                   .pluck('projects.id')
                   .uniq
      rescue StandardError => e
        Rails.logger.warn("[AgileSprintProjectsPatch] shared_sprint_project_ids fallback: #{e.class}: #{e.message}")
        project.shared_agile_sprints.map(&:shared_projects).map { |ps| ps.map(&:id) }.flatten.uniq
      end
    end
  end

  AgileQuery.prepend(TaskmanAgileSprintProjectsPatch) unless AgileQuery.ancestors.include?(TaskmanAgileSprintProjectsPatch)
end

# redmine_contacts_helpdesk collector - pluck customer IDs via join
# Original: issues_scope.joins(:customer).map(&:customer).map(&:id)
# Fixed: direct pluck from joined contacts table
# Toggle: TASKMAN_PATCH_HELPDESK_COLLECTOR
helpdesk_collector_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('HELPDESK_COLLECTOR')
TaskmanRuntimeCompat.log_patch('HELPDESK_COLLECTOR', helpdesk_collector_patch_enabled)
Rails.application.config.to_prepare do
  next unless helpdesk_collector_patch_enabled
  next unless defined?(HelpdeskDataCollectorBusiestTime)

  unless defined?(TaskmanHelpdeskCollectorPatch)
    module TaskmanHelpdeskCollectorPatch
      def customer_ids_for_issues(issues_scope)
        issues_scope.joins(:customer).pluck("#{Contact.table_name}.id")
      rescue StandardError => e
        Rails.logger.warn("[HelpdeskCollectorPatch] customer_ids_for_issues fallback: #{e.class}: #{e.message}")
        issues_scope.joins(:customer).map(&:customer).map(&:id)
      end
    end
  end

HelpdeskDataCollectorBusiestTime.prepend(TaskmanHelpdeskCollectorPatch) unless HelpdeskDataCollectorBusiestTime.ancestors.include?(TaskmanHelpdeskCollectorPatch)
end

# redmine_agile sprints context menu - memoize common_for_projects
# Original: common_for_projects called multiple times in view context
# Fixed: helper-level memoization to reuse the same result per request
# Toggle: TASKMAN_PATCH_AGILE_SPRINTS_CACHE
agile_sprints_cache_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('AGILE_SPRINTS_CACHE')
TaskmanRuntimeCompat.log_patch('AGILE_SPRINTS_CACHE', agile_sprints_cache_patch_enabled)
Rails.application.config.to_prepare do
  next unless agile_sprints_cache_patch_enabled

  unless defined?(TaskmanAgileSprintsCachePatch)
    module TaskmanAgileSprintsCachePatch
      def common_for_projects
        @eea_common_for_projects ||= super
      rescue StandardError => e
        Rails.logger.warn("[AgileSprintsCachePatch] common_for_projects fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  if defined?(AgileSprintsHelper)
    AgileSprintsHelper.prepend(TaskmanAgileSprintsCachePatch) unless AgileSprintsHelper.ancestors.include?(TaskmanAgileSprintsCachePatch)
  elsif defined?(ContextMenusController)
    ContextMenusController.prepend(TaskmanAgileSprintsCachePatch) unless ContextMenusController.ancestors.include?(TaskmanAgileSprintsCachePatch)
  end
end

# redmine_contacts deals statistics - pre-aggregate counts by status
# Original: view performs count per status (N+1)
# Fixed: controller computes grouped counts once
# Toggle: TASKMAN_PATCH_DEALS_STATS
deals_stats_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('DEALS_STATS')
TaskmanRuntimeCompat.log_patch('DEALS_STATS', deals_stats_patch_enabled)
Rails.application.config.to_prepare do
  next unless deals_stats_patch_enabled
  next unless defined?(DealsController)

  unless defined?(TaskmanDealsStatsPatch)
    module TaskmanDealsStatsPatch
      def index
        super
        if defined?(@deals_scope) && @deals_scope
          @eea_deals_count_by_status ||= @deals_scope.group(:status_id).count
        end
      rescue StandardError => e
        Rails.logger.warn("[DealsStatsPatch] index fallback: #{e.class}: #{e.message}")
      end
    end
  end

  DealsController.prepend(TaskmanDealsStatsPatch) unless DealsController.ancestors.include?(TaskmanDealsStatsPatch)
end

# redmine_contacts board deals counts - pre-aggregate counts by status
# Original: board view performs count per status (N+1)
# Fixed: controller computes grouped counts once
# Toggle: TASKMAN_PATCH_BOARD_DEALS
board_deals_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('BOARD_DEALS')
TaskmanRuntimeCompat.log_patch('BOARD_DEALS', board_deals_patch_enabled)
Rails.application.config.to_prepare do
  next unless board_deals_patch_enabled
  next unless defined?(DealsController)

  unless defined?(TaskmanBoardDealsPatch)
    module TaskmanBoardDealsPatch
      def board
        super
        if defined?(@deals_scope) && @deals_scope
          @eea_board_deals_count_by_status ||= @deals_scope.group(:status_id).count
        end
      rescue StandardError => e
        Rails.logger.warn("[BoardDealsPatch] board fallback: #{e.class}: #{e.message}")
      end
    end
  end

  DealsController.prepend(TaskmanBoardDealsPatch) unless DealsController.ancestors.include?(TaskmanBoardDealsPatch)
end

# redmine_resources utilization report - pre-load roles per user/project
# Original: roles_for_project called in nested user x project loop
# Fixed: preload memberships+roles and build lookup hash
# Toggle: TASKMAN_PATCH_UTILIZATION_ROLES
utilization_roles_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('UTILIZATION_ROLES')
TaskmanRuntimeCompat.log_patch('UTILIZATION_ROLES', utilization_roles_patch_enabled)
Rails.application.config.to_prepare do
  next unless utilization_roles_patch_enabled
  next unless defined?(ResourceBookingsController)

  unless defined?(TaskmanUtilizationRolesPatch)
    module TaskmanUtilizationRolesPatch
      def utilization_report
        super
        if defined?(@users) && defined?(@projects) && @users && @projects && defined?(Member)
          @eea_roles_by_user_project ||= Member
            .where(user_id: @users.map(&:id), project_id: @projects.map(&:id))
            .includes(:roles)
            .each_with_object({}) do |member, hash|
              hash[[member.user_id, member.project_id]] = member.roles
            end
        end
      rescue StandardError => e
        Rails.logger.warn("[UtilizationRolesPatch] utilization_report fallback: #{e.class}: #{e.message}")
      end
    end
  end

  ResourceBookingsController.prepend(TaskmanUtilizationRolesPatch) unless ResourceBookingsController.ancestors.include?(TaskmanUtilizationRolesPatch)
end

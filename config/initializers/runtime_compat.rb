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

# Redmine 6 nested-set locking expects a class-level advisory lock helper.
# Some runtime bundles miss that extension; provide a safe fallback.
# Scope: global AR class API; fallback is no-op wrapper that only yields block.
# Toggle: TASKMAN_PATCH_ADVISORY_LOCK
advisory_lock_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('ADVISORY_LOCK')
TaskmanRuntimeCompat.log_patch('ADVISORY_LOCK', advisory_lock_patch_enabled)
if advisory_lock_patch_enabled && !ActiveRecord::Base.respond_to?(:with_advisory_lock!)
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
# Scope: routing; only appends the legacy route if absent.
# Toggle: TASKMAN_PATCH_GLOBAL_BANNER_ROUTE
global_banner_route_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('GLOBAL_BANNER_ROUTE')
TaskmanRuntimeCompat.log_patch('GLOBAL_BANNER_ROUTE', global_banner_route_patch_enabled)
Rails.application.config.to_prepare do
  next unless global_banner_route_patch_enabled

  has_global_banner_route = Rails.application.routes.routes.any? do |route|
    route.defaults[:controller] == 'ai_helper/global_banner' &&
      route.defaults[:action] == 'show'
  end

  next if has_global_banner_route

  Rails.application.routes.append do
    get 'ai_helper/global_banner/:id',
        to: 'ai_helper/global_banner#show',
        as: :ai_helper_global_banner_legacy
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

# Inline query column options can be built more than once during the same
# view render. Cache per view-context + query object to avoid duplicate helper
# work without changing IssueQuery lifecycle.
# Scope: QueriesHelper only; memoized by query object id.
# Toggle: TASKMAN_PATCH_QUERY_INLINE_COLUMNS_CACHE
query_inline_columns_cache_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('QUERY_INLINE_COLUMNS_CACHE')
TaskmanRuntimeCompat.log_patch('QUERY_INLINE_COLUMNS_CACHE', query_inline_columns_cache_patch_enabled)
Rails.application.config.to_prepare do
  next unless query_inline_columns_cache_patch_enabled
  next unless defined?(QueriesHelper)

  unless defined?(TaskmanQueriesHelperInlineColumnsCachePatch)
    module TaskmanQueriesHelperInlineColumnsCachePatch
      def query_available_inline_columns_options(query = self.query)
        @taskman_inline_columns_options_cache ||= {}
        cache_key = query.object_id
        return @taskman_inline_columns_options_cache[cache_key] if @taskman_inline_columns_options_cache.key?(cache_key)

        @taskman_inline_columns_options_cache[cache_key] = super
      end
    end
  end

  unless QueriesHelper.ancestors.include?(TaskmanQueriesHelperInlineColumnsCachePatch)
    QueriesHelper.prepend(TaskmanQueriesHelperInlineColumnsCachePatch)
  end
end

# redmine_resources allocation chart spends significant CPU in render phase by
# repeatedly scanning bookings per day/user and rebuilding identical maps.
# Keep behavior unchanged but memoize deterministic computations per request.
# Scope: RedmineResources allocation chart render path only.
# Toggle: TASKMAN_PATCH_RESOURCE_ALLOCATION
resource_allocation_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('RESOURCE_ALLOCATION')
TaskmanRuntimeCompat.log_patch('RESOURCE_ALLOCATION', resource_allocation_patch_enabled)
Rails.application.config.to_prepare do
  next unless resource_allocation_patch_enabled
  next unless defined?(RedmineResources::Charts::AllocationChart)

  unless defined?(TaskmanResourceAllocationChartPerfPatch)
    module TaskmanResourceAllocationChartPerfPatch
      # Same input is requested multiple times during one render.
      def build_resource_bookings_map(resource_bookings, sort = false)
        @taskman_resource_bookings_map_cache ||= {}
        cache_key = [resource_bookings.object_id, sort]
        return @taskman_resource_bookings_map_cache[cache_key] if @taskman_resource_bookings_map_cache.key?(cache_key)

        @taskman_resource_bookings_map_cache[cache_key] = super
      end

      # Versions for a project/date window are reused across line rendering.
      def versions_by(project, from, to)
        @taskman_versions_by_cache ||= {}
        cache_key = [project.id, from, to]
        return @taskman_versions_by_cache[cache_key] if @taskman_versions_by_cache.key?(cache_key)

        @taskman_versions_by_cache[cache_key] = super
      end

      # Preserve original semantics, but use precomputed daily hours.
      def scheduled_hours_for(date, user, resource_bookings)
        return if non_working_week_days.include?(date.cwday) || resource_bookings.blank?
        return if holiday?(date)

        daily_hours = taskman_daily_hours_for_user(user, resource_bookings)
        value = daily_hours[date]
        value.positive? ? value : nil
      end

      private

      # Converts repeated O(days * bookings) scan into one per-request map build.
      # Keyed by user and booking collection identity to keep cache bounded.
      def taskman_daily_hours_for_user(user, resource_bookings)
        @taskman_daily_hours_for_user_cache ||= {}
        cache_key = [user.id, resource_bookings.object_id]
        return @taskman_daily_hours_for_user_cache[cache_key] if @taskman_daily_hours_for_user_cache.key?(cache_key)

        workday_length = workday_length_by(user)
        hours_by_date = Hash.new(0.0)

        Array(resource_bookings).each do |booking|
          booking_start = [booking.start_date.to_date, @date_from].max
          booking_end = [booking.get_end_date.to_date, @date_to].min
          next if booking_start > booking_end

          (booking_start..booking_end).each do |day|
            next if non_working_week_days.include?(day.cwday) || holiday?(day)

            hours_by_date[day] += booking.daily_hours(workday_length)
          end
        end

        @taskman_daily_hours_for_user_cache[cache_key] = hours_by_date
      end
    end
  end

  unless RedmineResources::Charts::AllocationChart.ancestors.include?(TaskmanResourceAllocationChartPerfPatch)
    RedmineResources::Charts::AllocationChart.prepend(TaskmanResourceAllocationChartPerfPatch)
  end
end

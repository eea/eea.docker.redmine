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

# Inline query column options - no caching, super is called directly each time.
# Query rewrite/deduplication is the real fix, not caching.
# Toggle: TASKMAN_PATCH_QUERY_INLINE_COLUMNS_CACHE
query_inline_columns_cache_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('QUERY_INLINE_COLUMNS_CACHE')
TaskmanRuntimeCompat.log_patch('QUERY_INLINE_COLUMNS_CACHE', query_inline_columns_cache_patch_enabled)
Rails.application.config.to_prepare do
  next unless query_inline_columns_cache_patch_enabled
  next unless defined?(QueriesHelper)

  unless defined?(TaskmanQueriesHelperInlineColumnsCachePatch)
    module TaskmanQueriesHelperInlineColumnsCachePatch
      def query_available_inline_columns_options(query = self.query)
        super
      end
    end
  end

  unless QueriesHelper.ancestors.include?(TaskmanQueriesHelperInlineColumnsCachePatch)
    QueriesHelper.prepend(TaskmanQueriesHelperInlineColumnsCachePatch)
  end
end

# redmine_resources allocation chart - keep O(days * bookings) logic but no memoization.
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
        super
      end

      # Versions for a project/date window are reused across line rendering.
      def versions_by(project, from, to)
        super
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

        hours_by_date
      end
    end
  end

  unless RedmineResources::Charts::AllocationChart.ancestors.include?(TaskmanResourceAllocationChartPerfPatch)
    RedmineResources::Charts::AllocationChart.prepend(TaskmanResourceAllocationChartPerfPatch)
  end
end
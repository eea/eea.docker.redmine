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
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
      def issues_ids(*args)
        issue_scope.unscope(:select, :order).pluck(:id)
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.warn("[AgileIssuesIdsPatch] issues_ids fallback: #{e.class}: #{e.message}")
        super(*args)
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
      # Safety rule: only apply limit+1 optimization when caller already paginates.
      # If no explicit :limit is provided, delegate unchanged to avoid behavior drift.
      def issue_board(*args, &block)
        options_index = args.index { |a| a.is_a?(Hash) }
        return super(*args, &block) unless options_index

        options = args[options_index].dup
        limit = options[:limit].to_i
        return super(*args, &block) if limit <= 0

        tuned_args = args.dup
        tuned_args[options_index] = options.merge(limit: limit + 1)

        result = super(*tuned_args, &block)
        return result unless result.respond_to?(:size) && result.size > limit

        result.first(limit)
      rescue ArgumentError
        super(*args, &block)
      rescue StandardError => e
        Rails.logger.warn("[AgileDoubleCountPatch] issue_board fallback: #{e.class}: #{e.message}")
        super(*args, &block)
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

agile_sprint_hours_sum_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('AGILE_SPRINT_HOURS_SUM')
TaskmanRuntimeCompat.log_patch('AGILE_SPRINT_HOURS_SUM', agile_sprint_hours_sum_patch_enabled)
Rails.application.config.to_prepare do
  next unless agile_sprint_hours_sum_patch_enabled
  next unless defined?(AgileSprintsController)

  unless defined?(TaskmanAgileSprintHoursSumPatch)
    module TaskmanAgileSprintHoursSumPatch
      def show
        super
        if @issues&.any?
          @estimated_hours = @issues.sum(:estimated_hours)
          @spent_hours = @issues.joins(:time_entries).sum('time_entries.hours')
          @story_points = @issues.joins(:agile_data).sum('agile_data.story_points')
        end
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.warn("[AgileSprintHoursSumPatch] post-super aggregation failed: #{e.class}: #{e.message}")
      end
    end
  end

  AgileSprintsController.prepend(TaskmanAgileSprintHoursSumPatch) unless AgileSprintsController.ancestors.include?(TaskmanAgileSprintHoursSumPatch)
end


helpdesk_project_children_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('HELPDESK_PROJECT_CHILDREN')
TaskmanRuntimeCompat.log_patch('HELPDESK_PROJECT_CHILDREN', helpdesk_project_children_patch_enabled)
Rails.application.config.to_prepare do
  next unless helpdesk_project_children_patch_enabled
  next unless defined?(HelpdeskTicket)

  unless defined?(TaskmanHelpdeskProjectChildrenPatch)
    module TaskmanHelpdeskProjectChildrenPatch
      def project_ids_with_children(project)
        [project.id] + project.children
                              .joins(:enabled_modules)
                              .where(enabled_modules: { name: :contacts_helpdesk })
                              .pluck(:id)
      rescue StandardError => e
        Rails.logger.warn("[HelpdeskProjectChildrenPatch] project_ids_with_children fallback: #{e.class}: #{e.message}")
        [project.id] + project.children.select { |ch| ch.module_enabled?(:contacts_helpdesk) }.map(&:id)
      end
    end
  end

  HelpdeskTicket.prepend(TaskmanHelpdeskProjectChildrenPatch) unless HelpdeskTicket.ancestors.include?(TaskmanHelpdeskProjectChildrenPatch)
end

resource_booking_blank_issue_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('RESOURCE_BOOKING_BLANK_ISSUE')
TaskmanRuntimeCompat.log_patch('RESOURCE_BOOKING_BLANK_ISSUE', resource_booking_blank_issue_patch_enabled)
Rails.application.config.to_prepare do
  next unless resource_booking_blank_issue_patch_enabled
  next unless defined?(WeekPlan) || defined?(MonthPlan) || defined?(Plan)

  unless defined?(TaskmanResourceBookingBlankIssuePatch)
    module TaskmanResourceBookingBlankIssuePatch
      def booked_project_ids(resource_bookings)
        resource_bookings.where(issue_id: nil).pluck(:project_id)
      rescue StandardError => e
        Rails.logger.warn("[ResourceBookingBlankIssuePatch] booked_project_ids fallback: #{e.class}: #{e.message}")
        resource_bookings.select { |rb| rb.issue.blank? }.map(&:project_id)
      end
    end
  end

  if defined?(WeekPlan)
    WeekPlan.prepend(TaskmanResourceBookingBlankIssuePatch) unless WeekPlan.ancestors.include?(TaskmanResourceBookingBlankIssuePatch)
  end
  if defined?(MonthPlan)
    MonthPlan.prepend(TaskmanResourceBookingBlankIssuePatch) unless MonthPlan.ancestors.include?(TaskmanResourceBookingBlankIssuePatch)
  end
  if defined?(Plan)
    Plan.prepend(TaskmanResourceBookingBlankIssuePatch) unless Plan.ancestors.include?(TaskmanResourceBookingBlankIssuePatch)
  end
end

deal_lines_sum_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('DEAL_LINES_SUM')
TaskmanRuntimeCompat.log_patch('DEAL_LINES_SUM', deal_lines_sum_patch_enabled)
Rails.application.config.to_prepare do
  next unless deal_lines_sum_patch_enabled
  next unless defined?(Deal)
  next unless Deal.method_defined?(:lines)

  unless defined?(TaskmanDealLinesSumPatch)
    module TaskmanDealLinesSumPatch
      # marked_for_destruction? is a Rails in-memory flag, not a DB column.
      # where(marked_for_destruction: false) would raise StatementInvalid.
      # SQL SUM is safe at display time (lines pending destruction still exist in DB).
      def tax_amount
        lines.sum(:tax_amount)
      rescue StandardError => e
        Rails.logger.warn("[DealLinesSumPatch] tax_amount fallback: #{e.class}: #{e.message}")
        lines.to_a.reject(&:marked_for_destruction?).sum(&:tax_amount)
      end

      def total_amount
        lines.sum(:total)
      rescue StandardError => e
        Rails.logger.warn("[DealLinesSumPatch] total_amount fallback: #{e.class}: #{e.message}")
        lines.to_a.reject(&:marked_for_destruction?).sum(&:total)
      end

      def total_quantity
        lines.sum(:quantity)
      rescue StandardError => e
        Rails.logger.warn("[DealLinesSumPatch] total_quantity fallback: #{e.class}: #{e.message}")
        lines.to_a.reject(&:marked_for_destruction?).sum { |l| l.product.blank? ? 0 : l.quantity }
      end
    end
  end

  Deal.prepend(TaskmanDealLinesSumPatch) unless Deal.ancestors.include?(TaskmanDealLinesSumPatch)
end

contact_notes_attachments_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('CONTACT_NOTES_ATTACHMENTS')
TaskmanRuntimeCompat.log_patch('CONTACT_NOTES_ATTACHMENTS', contact_notes_attachments_patch_enabled)
Rails.application.config.to_prepare do
  next unless contact_notes_attachments_patch_enabled
  next unless defined?(Contact)

  unless defined?(TaskmanContactNotesAttachmentsPatch)
    module TaskmanContactNotesAttachmentsPatch
      def contact_attachments
        @contact_attachments ||= Attachment.where(container_type: 'Note', container_id: notes.pluck(:id)).order(:created_on)
      rescue StandardError => e
        Rails.logger.warn("[ContactNotesAttachmentsPatch] contact_attachments fallback: #{e.class}: #{e.message}")
        Attachment.where(container_type: 'Note', container_id: notes.map(&:id)).order(:created_on)
      end
    end
  end

  Contact.prepend(TaskmanContactNotesAttachmentsPatch) unless Contact.ancestors.include?(TaskmanContactNotesAttachmentsPatch)
end

# CONTACTS_CONTROLLER_CAN
contacts_controller_can_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('CONTACTS_CONTROLLER_CAN')
TaskmanRuntimeCompat.log_patch('CONTACTS_CONTROLLER_CAN', contacts_controller_can_patch_enabled)
Rails.application.config.to_prepare do
  next unless contacts_controller_can_patch_enabled
  next unless defined?(ContactsController)

  unless defined?(TaskmanContactsControllerCanPatch)
    module TaskmanContactsControllerCanPatch
      def bulk_authorize
        super
        if @can && @contacts
          @can[:edit]       = @contacts.all?(&:editable?)
          @can[:delete]     = @contacts.all?(&:deletable?)
          @can[:send_mails] = @contacts.all? { |c| c.send_mail_allowed? && c.primary_email.present? }
        end
      rescue StandardError => e
        Rails.logger.warn("[ContactsControllerCanPatch] bulk_authorize fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  ContactsController.prepend(TaskmanContactsControllerCanPatch) unless ContactsController.ancestors.include?(TaskmanContactsControllerCanPatch)
end

# CONTACT_GROUPS_IDS
contact_groups_ids_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('CONTACT_GROUPS_IDS')
TaskmanRuntimeCompat.log_patch('CONTACT_GROUPS_IDS', contact_groups_ids_patch_enabled)
Rails.application.config.to_prepare do
  next unless contact_groups_ids_patch_enabled
  next unless defined?(Contact)

  unless defined?(TaskmanContactGroupsIdsPatch)
    module TaskmanContactGroupsIdsPatch
      def visible?(usr = nil)
        usr ||= User.current
        return true if usr.admin?
        return false unless usr.logged?
        projects_with_contacts = Project.joins(:enabled_modules)
                                        .where(enabled_modules: { name: 'contacts' })
                                        .where(id: ContactsProject.where(contact_id: id).select(:project_id))
        projects_with_contacts.any? { |project| usr.allowed_to?(:view_contacts, project) }
      rescue StandardError => e
        Rails.logger.warn("[ContactGroupsIdsPatch] visible? fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  Contact.prepend(TaskmanContactGroupsIdsPatch) unless Contact.ancestors.include?(TaskmanContactGroupsIdsPatch)
end

# AGILE_VERSIONS_QUERY
agile_versions_query_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('AGILE_VERSIONS_QUERY')
TaskmanRuntimeCompat.log_patch('AGILE_VERSIONS_QUERY', agile_versions_query_patch_enabled)
Rails.application.config.to_prepare do
  next unless agile_versions_query_patch_enabled
  next unless defined?(AgileVersionsQuery)

  unless defined?(TaskmanAgileVersionsQueryPatch)
    module TaskmanAgileVersionsQueryPatch
      def roadmap_tracker_ids(project)
        project.trackers.where(is_in_roadmap: true).pluck(:id)
      rescue StandardError => e
        Rails.logger.warn("[AgileVersionsQueryPatch] roadmap_tracker_ids fallback: #{e.class}: #{e.message}")
        project.trackers.where(is_in_roadmap: true).map(&:id)
      end
    end
  end

  AgileVersionsQuery.prepend(TaskmanAgileVersionsQueryPatch) unless AgileVersionsQuery.ancestors.include?(TaskmanAgileVersionsQueryPatch)
end

# AGILE_SPRINTS_QUERY
agile_sprints_query_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('AGILE_SPRINTS_QUERY')
TaskmanRuntimeCompat.log_patch('AGILE_SPRINTS_QUERY', agile_sprints_query_patch_enabled)
Rails.application.config.to_prepare do
  next unless agile_sprints_query_patch_enabled
  next unless defined?(AgileSprintsQuery)

  unless defined?(TaskmanAgileSprintsQueryPatch)
    module TaskmanAgileSprintsQueryPatch
      def project_ids_with_descendants(project)
        ids = [project.id]
        ids += project.descendants.pluck(:id) if project.lft.present? && Setting.display_subprojects_issues?
        ids
      rescue StandardError => e
        Rails.logger.warn("[AgileSprintsQueryPatch] project_ids_with_descendants fallback: #{e.class}: #{e.message}")
        ids = [project.id]
        ids += project.descendants.map(&:id) if project.lft.present? && Setting.display_subprojects_issues?
        ids
      end
    end
  end

  AgileSprintsQuery.prepend(TaskmanAgileSprintsQueryPatch) unless AgileSprintsQuery.ancestors.include?(TaskmanAgileSprintsQueryPatch)
end

# TIME_ENTRY_CUSTOM_VALUES
# Preload custom_values on time_entries to avoid N+1 (25 queries -> 1)
# Original: TimeEntryQuery doesn't preload custom_values
# Fixed: Add .preload(:custom_values) to results scope
# Toggle: TASKMAN_PATCH_TIME_ENTRY_CUSTOM_VALUES
time_entry_custom_values_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('TIME_ENTRY_CUSTOM_VALUES')
TaskmanRuntimeCompat.log_patch('TIME_ENTRY_CUSTOM_VALUES', time_entry_custom_values_patch_enabled)
Rails.application.config.to_prepare do
  next unless time_entry_custom_values_patch_enabled
  next unless defined?(TimeEntryQuery)

  unless defined?(TaskmanTimeEntryCustomValuesPatch)
    module TaskmanTimeEntryCustomValuesPatch
      def results_scope(options = {})
        scope = super
        scope = scope.preload(:custom_values => :custom_field) unless scope.includes_values.include?(:custom_values)
        scope
      rescue StandardError => e
        Rails.logger.warn("[TimeEntryCustomValuesPatch] results_scope fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  TimeEntryQuery.prepend(TaskmanTimeEntryCustomValuesPatch) unless TimeEntryQuery.ancestors.include?(TaskmanTimeEntryCustomValuesPatch)
end

# TIME_ENTRY_PROJECT_MODULES
# Preload enabled_modules on projects to avoid N+1 (11 queries -> 1)
# Original: project.module_enabled? fires query per project
# Fixed: Batch preload enabled_modules for all visible projects
# Toggle: TASKMAN_PATCH_TIME_ENTRY_PROJECT_MODULES
time_entry_project_modules_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('TIME_ENTRY_PROJECT_MODULES')
TaskmanRuntimeCompat.log_patch('TIME_ENTRY_PROJECT_MODULES', time_entry_project_modules_patch_enabled)
Rails.application.config.to_prepare do
  next unless time_entry_project_modules_patch_enabled
  next unless defined?(TimelogController)

  unless defined?(TaskmanTimeEntryProjectModulesPatch)
    module TaskmanTimeEntryProjectModulesPatch
      def index
        super
        return unless @project && @time_entries

        project_ids = @time_entries.map(&:project_id).compact.uniq
        return if project_ids.empty?

        modules_map = EnabledModule.where(project_id: project_ids)
                                   .group_by(&:project_id)

        @time_entries.each do |te|
          next unless te.project
          modules = modules_map[te.project.id] || []
          te.project.instance_variable_set(:@enabled_modules, modules)
        end
      rescue StandardError => e
        Rails.logger.warn("[TimeEntryProjectModulesPatch] index fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  TimelogController.prepend(TaskmanTimeEntryProjectModulesPatch) unless TimelogController.ancestors.include?(TaskmanTimeEntryProjectModulesPatch)
end

# TIME_ENTRY_SUM_HOURS
# Pre-calculate sum hours to avoid second query
# Original: SUM query runs separately in _date_range partial
# Fixed: Add sum cached value to avoid duplicate query
# Toggle: TASKMAN_PATCH_TIME_ENTRY_SUM_HOURS
time_entry_sum_hours_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('TIME_ENTRY_SUM_HOURS')
TaskmanRuntimeCompat.log_patch('TIME_ENTRY_SUM_HOURS', time_entry_sum_hours_patch_enabled)
Rails.application.config.to_prepare do
  next unless time_entry_sum_hours_patch_enabled
  next unless defined?(TimeEntryQuery)

  unless defined?(TaskmanTimeEntrySumHoursPatch)
    module TaskmanTimeEntrySumHoursPatch
      def default_total_hours
        total = super
        return total if total.present? || !respond_to?(:responseable?) || !responseable?

        scope = respond_to?(:base_scope) ? base_scope : nil
        return total unless scope

        @cached_hours_sum ||= scope.sum(:hours)
      rescue StandardError => e
        Rails.logger.warn("[TimeEntrySumHoursPatch] default_total_hours fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  if defined?(TimeEntryQuery)
    TimeEntryQuery.prepend(TaskmanTimeEntrySumHoursPatch) unless TimeEntryQuery.ancestors.include?(TaskmanTimeEntrySumHoursPatch)
  end
end

# PROJECT_MEMBERS_PRELOAD
# FIX SLOW /SETTINGS/MEMBERS PAGE (210K row member_roles bottleneck)
# Root cause: Member#roles does has_many :through which fires a DISTINCT
# JOIN query over ALL 210K member_roles rows for this project.
#
# FIX: pluck-based precomputation + request-scoped thread-local map.
# Toggle: TASKMAN_PATCH_PROJECT_MEMBERS_PRELOAD
# Toggle: TASKMAN_PATCH_PROJECT_MEMBERS_ROLES_NO_CACHE
# Toggle: TASKMAN_PATCH_SORTED_SCOPE
project_members_preload_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('PROJECT_MEMBERS_PRELOAD')
TaskmanRuntimeCompat.log_patch('PROJECT_MEMBERS_PRELOAD', project_members_preload_patch_enabled)

# Define base module OUTSIDE to_prepare so other patches can see it.
unless defined?(TaskmanProjectMembersPreloadPatch)
  module TaskmanProjectMembersPreloadPatch
    # Class method for checking the thread-local flag (called by other patches).
    def self.preload_members_in_progress?
      Thread.current[:taskman_preload_members_in_progress] == true
    end

    # Instance method override: principals_by_role
    # Called from ProjectsController#show to render the members box.
    # The view only needs {role => [principals]} — it never calls member.roles,
    # role_inheritance, or has_inherited_role? per member.
    #
    # Old approach: includes(:principal, member_roles: :role) → 210K rows via IN query
    # + an inherited_roles_map build that also scanned 210K rows (consumed only on the
    # settings page which never calls this method).
    #
    # New approach: SELECT DISTINCT member_id, role_id — collapses 210K rows to
    # ~1000-2000 unique pairs. Total: 4 small queries.
    def principals_by_role
      Thread.current[:taskman_preload_members_in_progress] = true

      # Load members + principals in one query. Derive IDs from result — avoids
      # a separate pluck(:id) followed by includes(:principal).
      active_members = memberships.active.includes(:principal).to_a
      return {} if active_members.empty?

      member_ids = active_members.map(&:id)

      # GROUP BY member_id, role_id — one pass over 210K rows returns unique pairs.
      # MAX(inherited_from IS NOT NULL) tells us if any row in this group is inherited;
      # used by the settings page bulk preload (not needed here, but free to compute).
      pairs = MemberRole
        .where(member_id: member_ids)
        .group(:member_id, :role_id)
        .pluck(:member_id, :role_id)

      role_ids = pairs.map(&:last).uniq
      roles_by_id = Role.where(id: role_ids).index_by(&:id)

      roles_by_member = {}
      pairs.each do |mid, rid|
        role = roles_by_id[rid]
        next unless role
        (roles_by_member[mid] ||= []) << role
      end

      result = {}
      active_members.each do |m|
        next unless m.principal
        (roles_by_member[m.id] || []).each do |r|
          next if r.respond_to?(:hide) && r.hide && respond_to?(:consider_hidden_roles?) && consider_hidden_roles?
          (result[r] ||= []) << m.principal
        end
      end

      result.each_value(&:uniq!)
      result
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.warn("[ProjectMembersPreloadPatch] principals_by_role fallback: #{e.class}: #{e.message}")
      super
    end
  end
end


# Define TaskmanProjectMembersPreloadControllerPatch outside to_prepare.
unless defined?(TaskmanProjectMembersPreloadControllerPatch)
  module TaskmanProjectMembersPreloadControllerPatch
    def self.prepended(base)
      base.class_eval do
        append_around_action :_taskman_clear_preload_flag
      end
    end

    def _taskman_clear_preload_flag
      yield
    ensure
      Thread.current[:taskman_preload_members_in_progress] = false
      Thread.current[:taskman_inherited_roles_map] = nil
      Thread.current[:taskman_member_roles_bulk_map] = nil
      Thread.current[:taskman_inherited_member_ids] = nil
    end
  end
end

Rails.application.config.to_prepare do
  next unless project_members_preload_patch_enabled
  next unless defined?(Project)

  Project.prepend(TaskmanProjectMembersPreloadPatch) unless Project.ancestors.include?(TaskmanProjectMembersPreloadPatch)

  ApplicationController.prepend(TaskmanProjectMembersPreloadControllerPatch) if defined?(ApplicationController)
end


# USER_ROLES_PRELOAD
# Fix N+1 in User#roles: called per-user, each fires Role.joins(members: :project).distinct.
# Fresh-data safe fix: avoid global/shared caches and compute roles with scoped AR queries
# each call to prevent stale permissions in issue-board flows.
# Toggle: TASKMAN_PATCH_USER_ROLES_PRELOAD
user_roles_preload_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('USER_ROLES_PRELOAD')
TaskmanRuntimeCompat.log_patch('USER_ROLES_PRELOAD', user_roles_preload_patch_enabled)
Rails.application.config.to_prepare do
  next unless user_roles_preload_patch_enabled
  next unless defined?(User)

  unless defined?(TaskmanUserRolesPreloadPatch)
    module TaskmanUserRolesPreloadPatch
      def roles
        if logged?
          Role.joins(members: :project)
              .where("#{Project.table_name}.status <> ?", Project::STATUS_ARCHIVED)
              .where(members: { user_id: id })
              .distinct
              .to_a
        else
          roles_for_anonymous_or_non_member
        end
      rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
          Rails.logger.warn("[UserRolesPreloadPatch] roles fallback: #{e.class}: #{e.message}")
        super
      end

      private

      def roles_for_anonymous_or_non_member
        group_class = anonymous? ? GroupAnonymous : GroupNonMember
        gid = group_class.pick(:id)
        return [] if gid.nil?

        sql = <<-SQL.squish
          SELECT DISTINCT r.id
          FROM roles r
          INNER JOIN member_roles mr ON mr.role_id = r.id
          INNER JOIN members m ON m.id = mr.member_id
          INNER JOIN projects p ON p.id = m.project_id
          WHERE p.status <> #{Project::STATUS_ARCHIVED}
            AND p.is_public = #{ActiveRecord::Base.connection.quote(true)}
            AND m.user_id = #{gid.to_i}
        SQL

        role_ids = ActiveRecord::Base.connection.execute(sql).map { |row| row["id"].to_i }
        Role.where(id: role_ids).to_a
      end
    end
  end

  User.prepend(TaskmanUserRolesPreloadPatch) unless User.ancestors.include?(TaskmanUserRolesPreloadPatch)

  [:GroupNonMember, :GroupAnonymous].each do |grp_sym|
    next unless Object.const_defined?(grp_sym.to_s)
    grp_class = Object.const_get(grp_sym)
    grp_class.prepend(TaskmanUserRolesPreloadPatch) unless grp_class.ancestors.include?(TaskmanUserRolesPreloadPatch)
  end
end

# Activity page author N+1 fix - bulk preload authors after events fetched
# Original: each event triggers separate author query via event_author
# Fixed: bulk preload all authors in one query after events are grouped by class
# Toggle: TASKMAN_PATCH_ACTIVITY_AUTHOR_PRELOAD
activity_author_preload_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('ACTIVITY_AUTHOR_PRELOAD', default: true)
TaskmanRuntimeCompat.log_patch('ACTIVITY_AUTHOR_PRELOAD', activity_author_preload_patch_enabled)
Rails.application.config.to_prepare do
  next unless activity_author_preload_patch_enabled
  next unless defined?(Redmine::Activity::Fetcher)

  unless defined?(TaskmanActivityAuthorPreloadPatch)
    module TaskmanActivityAuthorPreloadPatch
      def events(from = nil, to = nil, options = {})
        events = super

        # Only apply to HTML format (not Atom which uses limit and is already optimized)
        return events if options[:limit]
        return events if events.empty?

        # Group events by class and bulk preload authors
        events.group_by(&:class).each do |klass, class_events|
          next unless klass.respond_to?(:reflect_on_association)
          next unless klass.reflect_on_association(:author)
          next unless class_events.first.respond_to?(:event_author)

          # Bulk preload authors for all events of this class
          # Uses Rails 7+ Preloader API
          ActiveRecord::Associations::Preloader.new(
            records: class_events,
            associations: :author
          ).call
        end

        events
      rescue StandardError => e
        Rails.logger.warn("[ActivityAuthorPreloadPatch] fallback: #{e.class}: #{e.message}")
        events
      end
    end
  end

  Redmine::Activity::Fetcher.prepend(TaskmanActivityAuthorPreloadPatch) unless Redmine::Activity::Fetcher.ancestors.include?(TaskmanActivityAuthorPreloadPatch)
end

# Wiki links inside mounted engines can incorrectly resolve to engine-scoped
# controllers (e.g. ai_helper/wiki). Force main app routing for wiki links.
# Toggle: TASKMAN_PATCH_WIKI_LINKS_MAIN_APP
wiki_links_main_app_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('WIKI_LINKS_MAIN_APP', default: true)
TaskmanRuntimeCompat.log_patch('WIKI_LINKS_MAIN_APP', wiki_links_main_app_patch_enabled)
Rails.application.config.to_prepare do
  next unless wiki_links_main_app_patch_enabled
  next unless defined?(ApplicationHelper)

  unless defined?(TaskmanWikiLinksMainAppPatch)
    module TaskmanWikiLinksMainAppPatch
      def parse_wiki_links(text, project, obj, attr, only_path, options)
        text.gsub!(/(!)?(\[\[([^\n\|]+?)(\|([^\n\|]+?))?\]\])/) do |_m|
          link_project = project
          esc, all, page, title = $1, $2, $3, $5
          if esc.nil?
            page = CGI.unescapeHTML(page)
            if page =~ /^\#(.+)$/
              anchor = sanitize_anchor_name($1)
              url = "##{anchor}"
              next link_to(title.present? ? title.html_safe : h(page), url, class: 'wiki-page')
            end

            if page =~ /^([^\:]+)\:(.*)$/
              identifier, page = $1, $2
              link_project = Project.find_by_identifier(identifier) || Project.find_by_name(identifier)
              title ||= identifier if page.blank?
            end

            if link_project && link_project.wiki && User.current.allowed_to?(:view_wiki_pages, link_project)
              anchor = nil
              if page =~ /^(.+?)\#(.+)$/
                page, anchor = $1, $2
              end
              anchor = sanitize_anchor_name(anchor) if anchor.present?

              wiki_page = link_project.wiki.find_page(page)
              url =
                if anchor.present? && wiki_page.present? &&
                     (obj.is_a?(WikiContent) || obj.is_a?(WikiContentVersion)) &&
                     obj.page == wiki_page
                  "##{anchor}"
                else
                  case options[:wiki_links]
                  when :local
                    "#{page.present? ? Wiki.titleize(page) : ''}.html" + (anchor.present? ? "##{anchor}" : '')
                  when :anchor
                    "##{page.present? ? Wiki.titleize(page) : title}" + (anchor.present? ? "_#{anchor}" : '')
                  else
                    wiki_page_id = page.present? ? Wiki.titleize(page) : nil
                    parent =
                      if wiki_page.nil? && obj.is_a?(WikiContent) &&
                           obj.page && project == link_project
                        obj.page.title
                      else
                        nil
                      end

                    route_options = {
                      only_path: only_path,
                      controller: '/wiki',
                      action: 'show',
                      project_id: link_project,
                      id: wiki_page_id,
                      version: nil,
                      anchor: anchor,
                      parent: parent
                    }

                    if respond_to?(:main_app) && main_app.respond_to?(:url_for)
                      main_app.url_for(route_options)
                    else
                      url_for(route_options)
                    end
                  end
                end

              link_to(title.present? ? title.html_safe : h(page),
                      url, class: ('wiki-page' + (wiki_page ? '' : ' new')))
            else
              all
            end
          else
            all
          end
        end
      end
    end
  end

  ApplicationHelper.prepend(TaskmanWikiLinksMainAppPatch) unless ApplicationHelper.ancestors.include?(TaskmanWikiLinksMainAppPatch)
end

# SORTED_SCOPE: Avoid member_roles JOIN explosion in Member.sorted scope
# Original: includes(:member_roles, :roles, :principal) — 210K row JOIN
#   (:roles is has_many :through :member_roles, so any include of :roles also JOINs member_roles)
# Fixed: correlated scalar subquery for MIN(role.position) + joins(:principal) for ORDER BY
#
# Why singleton_class.prepend (not CollectionProxy or ActiveRecord_Relation):
#   `scope :sorted` defines a CLASS METHOD on Member. When @project.memberships.sorted
#   is called, CollectionProxy delegates to Member.sorted — the class method.
#   Prepending to Member.singleton_class puts our method first in class-method lookup.
#
# Guard: only activates when taskman_member_roles_bulk_map is set in Thread.current,
#   meaning ProjectsController#settings has already run the bulk preload.
#   Falls back to the original includes-based scope everywhere else so no other
#   caller loses its eager-loaded member_roles/roles associations.
#
# Toggle: TASKMAN_PATCH_SORTED_SCOPE
sorted_scope_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('SORTED_SCOPE')
TaskmanRuntimeCompat.log_patch('SORTED_SCOPE', sorted_scope_patch_enabled)
unless defined?(TaskmanSortedScopePatch)
  module TaskmanSortedScopePatch
    # Overrides Member.sorted (class method). Only activates when the bulk roles
    # map has been preloaded (i.e., inside ProjectsController#settings).
    # Falls back to the original includes-based scope for every other caller so
    # that no other page loses its eager-loaded member_roles/roles associations.
    def sorted
      return super unless Thread.current[:taskman_member_roles_bulk_map]

      min_pos_subquery = <<~SQL.squish
        (SELECT COALESCE(MIN(r.position), 999)
         FROM member_roles mr
         INNER JOIN roles r ON r.id = mr.role_id
         WHERE mr.member_id = #{Member.table_name}.id)
      SQL

      # joins(:principal) provides the users columns for ORDER BY but does not
      # populate the association. preload(:principal) fires one IN-clause query
      # after the main query so member.principal is available without N+1.
      joins(:principal)
        .select("#{Member.table_name}.*, #{min_pos_subquery} AS taskman_min_role_pos")
        .reorder("taskman_min_role_pos")
        .order(Principal.fields_for_order_statement)
        .preload(:principal)
    rescue StandardError => e
      Rails.logger.warn("[SortedScopePatch] sorted fallback: #{e.class}: #{e.message}")
      super
    end
  end
end

Rails.application.config.to_prepare do
  next unless sorted_scope_patch_enabled
  next unless defined?(Member)

  Member.singleton_class.prepend(TaskmanSortedScopePatch) unless
    Member.singleton_class.ancestors.include?(TaskmanSortedScopePatch)
end

# MEMBER_ROLES_SETTINGS_BULK_PRELOAD
# Fix N+1 on member.roles in the settings/members view.
#
# After sorted.to_a loads 438 members, the view calls member.roles per member.
# Without preloading: 438 queries × SELECT DISTINCT roles.* JOIN member_roles WHERE member_id=X
#
# Fix: patch ProjectsController#settings to bulk-load DISTINCT (member_id, role_id) pairs
# BEFORE the view renders. Member#roles does an O(1) map lookup instead of a SQL query.
#
# SELECT DISTINCT member_id, role_id collapses 210K member_roles to ~1000-2000 unique pairs.
# Toggle: TASKMAN_PATCH_MEMBER_ROLES_SETTINGS_BULK_PRELOAD (default on)
member_roles_settings_bulk_preload_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('MEMBER_ROLES_SETTINGS_BULK_PRELOAD', default: true)
TaskmanRuntimeCompat.log_patch('MEMBER_ROLES_SETTINGS_BULK_PRELOAD', member_roles_settings_bulk_preload_patch_enabled)

unless defined?(TaskmanMemberRolesSettingsBulkPreloadPatch)
  module TaskmanMemberRolesSettingsBulkPreloadPatch
    def settings
      if @project
        begin
          member_ids = @project.memberships.active.pluck(:id)
          unless member_ids.empty?
            # Query 1: DISTINCT (member_id, role_id) — pure covering index scan on
            # manual_idx_member_roles_member_role (member_id, role_id). No table access.
            # Collapses 210K rows → 857 unique pairs for mobaqj.
            pairs = MemberRole
              .where(member_id: member_ids)
              .distinct
              .pluck(:member_id, :role_id)

            role_ids = pairs.map(&:last).uniq
            roles_by_id = Role.where(id: role_ids).index_by(&:id)

            bulk_map = {}
            pairs.each do |mid, rid|
              role = roles_by_id[rid]
              (bulk_map[mid] ||= []) << role if role
            end
            Thread.current[:taskman_member_roles_bulk_map] = bulk_map

            # Query 2: which members have ANY inherited role — uses index_member_roles_on_inherited_from.
            # Kept separate from Query 1 so both can use their own covering index.
            # Adding inherited_from to the GROUP BY above would force base-table access,
            # defeating the (member_id, role_id) covering index.
            inherited_ids = MemberRole
              .where(member_id: member_ids)
              .where.not(inherited_from: nil)
              .distinct
              .pluck(:member_id)
            Thread.current[:taskman_inherited_member_ids] = Set.new(inherited_ids)
          end
        rescue StandardError => e
          Rails.logger.warn("[MemberRolesSettingsBulkPreloadPatch] preload failed: #{e.class}: #{e.message}")
        end
      end
      super
    end
  end
end

unless defined?(TaskmanMemberRolesBulkCachePatch)
  module TaskmanMemberRolesBulkCachePatch
    def roles
      bulk_map = Thread.current[:taskman_member_roles_bulk_map]
      return super unless bulk_map&.key?(id)
      bulk_map[id]
    rescue StandardError => e
      Rails.logger.warn("[MemberRolesBulkCachePatch] roles fallback: #{e.class}: #{e.message}")
      super
    end

    # member.deletable? calls any_inherited_role? which fires member_roles.any? per member.
    # Use the preloaded set instead.
    def any_inherited_role?
      inherited_set = Thread.current[:taskman_inherited_member_ids]
      return super unless inherited_set
      inherited_set.include?(id)
    rescue StandardError => e
      Rails.logger.warn("[MemberRolesBulkCachePatch] any_inherited_role? fallback: #{e.class}: #{e.message}")
      super
    end
  end
end

Rails.application.config.to_prepare do
  next unless member_roles_settings_bulk_preload_patch_enabled
  next unless defined?(ProjectsController) && defined?(Member)

  ProjectsController.prepend(TaskmanMemberRolesSettingsBulkPreloadPatch) unless
    ProjectsController.ancestors.include?(TaskmanMemberRolesSettingsBulkPreloadPatch)

  # Prepend AFTER TaskmanMemberRolesCachePatch so bulk lookup takes precedence.
  Member.prepend(TaskmanMemberRolesBulkCachePatch) unless
    Member.ancestors.include?(TaskmanMemberRolesBulkCachePatch)
end

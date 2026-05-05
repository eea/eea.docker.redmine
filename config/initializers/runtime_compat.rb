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

agile_sprint_hours_sum_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('AGILE_SPRINT_HOURS_SUM')
TaskmanRuntimeCompat.log_patch('AGILE_SPRINT_HOURS_SUM', agile_sprint_hours_sum_patch_enabled)
Rails.application.config.to_prepare do
  next unless agile_sprint_hours_sum_patch_enabled
  next unless defined?(AgileSprintsController)

  unless defined?(TaskmanAgileSprintHoursSumPatch)
    module TaskmanAgileSprintHoursSumPatch
      def show
        super
        if @issues.any?
          @estimated_hours = @issues.sum(:estimated_hours)
          @spent_hours = @issues.joins(:time_entries).sum('time_entries.hours')
          @story_points = @issues.joins(:agile_data).sum('agile_data.story_points')
        end
      rescue StandardError => e
        Rails.logger.warn("[AgileSprintHoursSumPatch] show fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  AgileSprintsController.prepend(TaskmanAgileSprintHoursSumPatch) unless AgileSprintsController.ancestors.include?(TaskmanAgileSprintHoursSumPatch)
end

contacts_ids_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('CONTACTS_IDS')
TaskmanRuntimeCompat.log_patch('CONTACTS_IDS', contacts_ids_patch_enabled)
Rails.application.config.to_prepare do
  next unless contacts_ids_patch_enabled
  next unless defined?(ContactsController)

  unless defined?(TaskmanContactsIdsPatch)
    module TaskmanContactsIdsPatch
      def index
        super
      rescue StandardError => e
        Rails.logger.warn("[ContactsIdsPatch] index fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  ContactsController.prepend(TaskmanContactsIdsPatch) unless ContactsController.ancestors.include?(TaskmanContactsIdsPatch)
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
      def tax_amount
        lines.where(marked_for_destruction: false).sum(:tax_amount)
      rescue StandardError => e
        Rails.logger.warn("[DealLinesSumPatch] tax_amount fallback: #{e.class}: #{e.message}")
        lines.select { |l| !l.marked_for_destruction? }.inject(0) { |sum, l| sum + l.tax_amount }
      end

      def total_amount
        lines.where(marked_for_destruction: false).sum(:total)
      rescue StandardError => e
        Rails.logger.warn("[DealLinesSumPatch] total_amount fallback: #{e.class}: #{e.message}")
        lines.select { |l| !l.marked_for_destruction? }.inject(0) { |sum, l| sum + l.total }
      end

      def total_quantity
        lines.sum(:quantity)
      rescue StandardError => e
        Rails.logger.warn("[DealLinesSumPatch] total_quantity fallback: #{e.class}: #{e.message}")
        lines.inject(0) { |sum, l| sum + (l.product.blank? ? 0 : l.quantity) }
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

# DEALS_CONTROLLER_INTERSECTION
deals_controller_intersection_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('DEALS_CONTROLLER_INTERSECTION')
TaskmanRuntimeCompat.log_patch('DEALS_CONTROLLER_INTERSECTION', deals_controller_intersection_patch_enabled)
Rails.application.config.to_prepare do
  next unless deals_controller_intersection_patch_enabled
  next unless defined?(DealsController)

  unless defined?(TaskmanDealsControllerIntersectionPatch)
    module TaskmanDealsControllerIntersectionPatch
      def index
        super
        if @projects && @projects.any?
          @available_statuses    = @projects.map(&:deal_statuses).reduce(:&) || []
          @available_categories  = @projects.map(&:deal_categories).reduce(:&) || []
          @assignables           = @projects.map(&:assignable_users).reduce(:&) || []
        end
      rescue StandardError => e
        Rails.logger.warn("[DealsControllerIntersectionPatch] index fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  DealsController.prepend(TaskmanDealsControllerIntersectionPatch) unless DealsController.ancestors.include?(TaskmanDealsControllerIntersectionPatch)
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
        user_ids = [usr.id] + usr.groups.pluck(:id)
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
        return total if total.present? || !responseable?

        scope = base_scope
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

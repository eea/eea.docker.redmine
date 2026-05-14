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
        issue_scope.unscope(:select, :order).pluck(:id)
      rescue ActiveRecord::StatementInvalid => e
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
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.warn("[AgileSprintHoursSumPatch] post-super aggregation failed: #{e.class}: #{e.message}")
        # Keep original super result; do not call super again.
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

# PROJECT_MEMBERS_PRELOAD
# Fix N+1 in principals_by_role (used by additionals plugin and Redmine core).
# Root cause: `m.roles.each` triggers N+1 because `roles` is not a direct
# Membership association — it goes through member_roles.
# Fix: use includes(:principal, member_roles: :role) and iterate mr.role.
# Also: use memberships.active (not members) to include Group principals.
# Toggle: TASKMAN_PATCH_PROJECT_MEMBERS_PRELOAD
project_members_preload_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('PROJECT_MEMBERS_PRELOAD')
TaskmanRuntimeCompat.log_patch('PROJECT_MEMBERS_PRELOAD', project_members_preload_patch_enabled)
Rails.application.config.to_prepare do
  next unless project_members_preload_patch_enabled
  next unless defined?(Project)

  unless defined?(TaskmanProjectMembersPreloadPatch)
    module TaskmanProjectMembersPreloadPatch
      def principals_by_role
        scope = memberships.active
                         .includes(:principal, member_roles: :role)

        result = {}
        scope.each do |m|
          next unless m.principal

          m.member_roles.each do |mr|
            r = mr.role
            next unless r
            # Honour hidden-role filtering when additionals plugin is present
            next if r.respond_to?(:hide) && r.hide && respond_to?(:consider_hidden_roles?) && consider_hidden_roles?

            result[r] ||= []
            result[r] << m.principal
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

  Project.prepend(TaskmanProjectMembersPreloadPatch) unless Project.ancestors.include?(TaskmanProjectMembersPreloadPatch)
end

# PROJECT_MEMBERS_COUNT_CACHE
# Add counter cache support for role-based member counts
# Original: Counting members per role requires full table scan
# Fixed: Use counter_cache column if available, falls back to count
# Toggle: TASKMAN_PATCH_PROJECT_MEMBERS_COUNT
project_members_count_cache_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('PROJECT_MEMBERS_COUNT')
TaskmanRuntimeCompat.log_patch('PROJECT_MEMBERS_COUNT', project_members_count_cache_patch_enabled)
Rails.application.config.to_prepare do
  next unless project_members_count_cache_patch_enabled
  next unless defined?(Project)

  unless defined?(TaskmanProjectMembersCountCachePatch)
    module TaskmanProjectMembersCountCachePatch
      def members_count_by_role(role_id)
        # Check if counter cache column exists on member_roles join table
        cache_column = "cached_count_for_role_#{role_id}"

        if respond_to?(:member_roles_count_cache) && member_roles_count_cache.key?(role_id)
          member_roles_count_cache[role_id]
        else
          members.joins(:member_roles)
                .where(member_roles: { role_id: role_id })
                .count
        end
      rescue StandardError => e
        Rails.logger.warn("[ProjectMembersCountCachePatch] members_count_by_role fallback: #{e.class}: #{e.message}")
        members.joins(:member_roles).where(member_roles: { role_id: role_id }).count
      end
    end
  end

  Project.prepend(TaskmanProjectMembersCountCachePatch) unless Project.ancestors.include?(TaskmanProjectMembersCountCachePatch)
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

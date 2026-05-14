# frozen_string_literal: true

# Usage:
#   bundle exec rails runner performance_findings/scripts/runtime_patch_status.rb
#
# Guardrail (required):
#   PATCH_STATUS_ALLOW=1 bundle exec rails runner performance_findings/scripts/runtime_patch_status.rb
#
# This script is intentionally execution-context scoped (rails runner) and does not
# expose an HTTP endpoint.

allow = ENV['PATCH_STATUS_ALLOW']
raise 'PATCH_STATUS_ALLOW=1 is required to run runtime patch status' unless allow == '1'

PATCHES = [
  ['AGILE_QUERY', 'TaskmanAgileQueryPerfPatch', 'AgileQuery'],
  ['AGILE_ISSUES_IDS', 'TaskmanAgileIssuesIdsPatch', 'AgileQuery'],
  ['RESOURCE_BOOKING_QUERY', 'TaskmanResourceBookingQueryPatch', 'ResourceBookingQuery'],
  ['AGILE_DOUBLE_COUNT', 'TaskmanAgileDoubleCountPatch', 'AgileQuery'],
  ['AGILE_DESCENDANTS_JOIN', 'TaskmanAgileDescendantsJoinPatch', 'AgileQuery'],
  ['AGILE_SPRINT_PROJECTS', 'TaskmanAgileSprintProjectsPatch', 'AgileQuery'],
  ['HELPDESK_COLLECTOR', 'TaskmanHelpdeskCollectorPatch', 'HelpdeskDataCollectorBusiestTime'],
  ['AGILE_SPRINT_HOURS_SUM', 'TaskmanAgileSprintHoursSumPatch', 'AgileSprintsController'],
  ['CONTACTS_IDS', 'TaskmanContactsIdsPatch', 'ContactsController'],
  ['HELPDESK_PROJECT_CHILDREN', 'TaskmanHelpdeskProjectChildrenPatch', 'HelpdeskTicket'],
  ['RESOURCE_BOOKING_BLANK_ISSUE', 'TaskmanResourceBookingBlankIssuePatch', 'WeekPlan|MonthPlan|Plan'],
  ['DEAL_LINES_SUM', 'TaskmanDealLinesSumPatch', 'Deal'],
  ['CONTACT_NOTES_ATTACHMENTS', 'TaskmanContactNotesAttachmentsPatch', 'Contact'],
  ['CONTACTS_CONTROLLER_CAN', 'TaskmanContactsControllerCanPatch', 'ContactsController'],
  ['CONTACT_GROUPS_IDS', 'TaskmanContactGroupsIdsPatch', 'Contact'],
  ['AGILE_VERSIONS_QUERY', 'TaskmanAgileVersionsQueryPatch', 'AgileVersionsQuery'],
  ['AGILE_SPRINTS_QUERY', 'TaskmanAgileSprintsQueryPatch', 'AgileSprintsQuery'],
  ['TIME_ENTRY_CUSTOM_VALUES', 'TaskmanTimeEntryCustomValuesPatch', 'TimeEntryQuery'],
  ['TIME_ENTRY_PROJECT_MODULES', 'TaskmanTimeEntryProjectModulesPatch', 'TimelogController'],
  ['TIME_ENTRY_SUM_HOURS', 'TaskmanTimeEntrySumHoursPatch', 'TimeEntryQuery'],
  ['PROJECT_MEMBERS_PRELOAD', 'TaskmanProjectMembersPreloadPatch', 'Project'],
  ['PROJECT_MEMBERS_COUNT', 'TaskmanProjectMembersCountCachePatch', 'Project'],
  ['USER_ROLES_PRELOAD', 'TaskmanUserRolesPreloadPatch', 'User|GroupNonMember|GroupAnonymous']
].freeze

def patch_enabled?(name)
  raw = ENV.fetch("TASKMAN_PATCH_#{name}", '0').to_s.strip.downcase
  !%w[0 false no off].include?(raw)
end

def const_defined_safe?(name)
  name.split('::').inject(Object) { |ctx, part| ctx.const_get(part) }
  true
rescue NameError
  false
end

def prepended?(module_name, targets)
  return false unless const_defined_safe?(module_name)

  mod = module_name.split('::').inject(Object) { |ctx, part| ctx.const_get(part) }

  targets.split('|').any? do |target_name|
    next false unless const_defined_safe?(target_name)

    target = target_name.split('::').inject(Object) { |ctx, part| ctx.const_get(part) }
    target.ancestors.include?(mod)
  end
end

rows = PATCHES.map do |toggle, mod, targets|
  {
    patch: toggle,
    env_key: "TASKMAN_PATCH_#{toggle}",
    enabled: patch_enabled?(toggle),
    module_defined: const_defined_safe?(mod),
    prepended: prepended?(mod, targets),
    targets: targets
  }
end

puts 'Patch Runtime Status'
puts '-' * 100
puts format('%-34s %-8s %-8s %-10s %s', 'ENV KEY', 'ENABLED', 'MODULE', 'PREPENDED', 'TARGETS')
puts '-' * 100
rows.each do |r|
  puts format('%-34s %-8s %-8s %-10s %s',
              r[:env_key], r[:enabled], r[:module_defined], r[:prepended], r[:targets])
end

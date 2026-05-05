#!/usr/bin/env ruby
# frozen_string_literal: true

# EEA Performance Patches Validation Script
# Validates all 11 EEA performance patches are properly loaded and functional

require 'fileutils'

results = []
fail_count = 0
pass_count = 0

def check(name, condition, details = nil)
  if condition
    puts "PASS: #{name}"
    [true, nil]
  else
    puts "FAIL: #{name}"
    puts "  -> #{details}" if details
    [false, details]
  end
end

puts '=' * 60
puts 'EEA Performance Patches Validation'
puts '=' * 60
puts

ENV['SECRET_KEY_BASE'] = 'a' * 64
ENV['RAILS_ENV'] = 'production'

env_paths = [
  '/usr/src/redmine/config/environment.rb',
  '/app/config/environment.rb'
]

env_loaded = false
env_paths.each do |env_path|
  next unless File.exist?(env_path)

  begin
    require env_path
    puts "Rails environment loaded from: #{env_path}"
    env_loaded = true
    break
  rescue StandardError => e
    puts "Warning: Could not load Rails env from #{env_path}: #{e.message[0..200]}"
  end
end

puts 'Warning: Could not load Rails environment from any known path' unless env_loaded

puts

# ============================================================================
# Section 1: Plugin Classes Loaded
# ============================================================================
puts '=' * 60
puts 'Section 1: Plugin Classes Loaded'
puts '=' * 60

classes = {
  'AgileQuery' => defined?(AgileQuery),
  'ResourceBooking' => defined?(ResourceBooking),
  'Contact' => defined?(Contact),
  'DealsController' => defined?(DealsController),
  'ResourceBookingsController' => defined?(ResourceBookingsController),
  'AgileSprint' => defined?(AgileSprint)
}

classes.each do |name, defined|
  passed, = check("#{name} defined", defined)
  passed ? pass_count += 1 : fail_count += 1
  results << { name: "Plugin class: #{name}", passed: passed }
end

plugin_dir_exists = File.exist?('/usr/src/redmine/plugins/redmine_eea_patches')
_, e = check('redmine_eea_patches plugin directory exists', plugin_dir_exists,
             'Plugin directory /usr/src/redmine/plugins/redmine_eea_patches does not exist')
e.nil? ? pass_count += 1 : fail_count += 1
results << { name: 'Plugin: redmine_eea_patches', passed: e.nil? }

helpdesk_defined = defined?(HelpdeskTicket) || defined?(HelpdeskTicket::Ticket)
if helpdesk_defined
  passed, = check('HelpdeskTicket defined', true)
  pass_count += 1
  results << { name: 'Plugin class: HelpdeskTicket', passed: true }
else
  puts "\nNOTE: HelpdeskTicket not defined - helpdesk plugin may not be mounted at runtime."
  puts 'This is expected if redmine_contacts_helpdesk is an addon.'
end

puts

# ============================================================================
# Section 2: TaskmanRuntimeCompat Helpers
# ============================================================================
puts '=' * 60
puts 'Section 2: TaskmanRuntimeCompat Helpers'
puts '=' * 60

_, e = check('TaskmanRuntimeCompat module defined', defined?(TaskmanRuntimeCompat))
e.nil? ? pass_count += 1 : fail_count += 1
results << { name: 'TaskmanRuntimeCompat defined', passed: e.nil? }

if defined?(TaskmanRuntimeCompat)
  _, e = check('patch_enabled? method exists', TaskmanRuntimeCompat.respond_to?(:patch_enabled?))
  e.nil? ? pass_count += 1 : fail_count += 1
  results << { name: 'patch_enabled? method', passed: e.nil? }

  _, e = check('log_patch method exists', TaskmanRuntimeCompat.respond_to?(:log_patch))
  e.nil? ? pass_count += 1 : fail_count += 1
  results << { name: 'log_patch method', passed: e.nil? }
else
  fail_count += 2
  results << { name: 'patch_enabled? method', passed: false }
  results << { name: 'log_patch method', passed: false }
end

puts

# ============================================================================
# Section 3: All 17 Patches in runtime_compat.rb
# ============================================================================
puts '=' * 60
puts 'Section 3: All 17 Patches - Toggle AND Module Exist'
puts '=' * 60

# Define the 17 patches with their expected module names
patches = {
  'AGILE_QUERY' => 'TaskmanAgileQueryPerfPatch',
  'AGILE_ISSUES_IDS' => 'TaskmanAgileIssuesIdsPatch',
  'RESOURCE_BOOKING_QUERY' => 'TaskmanResourceBookingQueryPatch',
  'RESOURCE_BOOKING_SUM' => 'TaskmanResourceBookingSumPatch',
  'AGILE_DOUBLE_COUNT' => 'TaskmanAgileDoubleCountPatch',
  'AGILE_DESCENDANTS_JOIN' => 'TaskmanAgileDescendantsJoinPatch',
  'AGILE_SPRINT_PROJECTS' => 'TaskmanAgileSprintProjectsPatch',
  'HELPDESK_COLLECTOR' => 'TaskmanHelpdeskCollectorPatch',
  'AGILE_SPRINT_HOURS_SUM' => 'TaskmanAgileSprintHoursSumPatch',
  'CONTACTS_IDS' => 'TaskmanContactsIdsPatch',
  'HELPDESK_PROJECT_CHILDREN' => 'TaskmanHelpdeskProjectChildrenPatch',
  'RESOURCE_BOOKING_BLANK_ISSUE' => 'TaskmanResourceBookingBlankIssuePatch',
  'DEAL_LINES_SUM' => 'TaskmanDealLinesSumPatch',
  'CONTACT_NOTES_ATTACHMENTS' => 'TaskmanContactNotesAttachmentsPatch',
  'TIME_ENTRY_CUSTOM_VALUES' => 'TaskmanTimeEntryCustomValuesPatch',
  'TIME_ENTRY_PROJECT_MODULES' => 'TaskmanTimeEntryProjectModulesPatch',
  'TIME_ENTRY_SUM_HOURS' => 'TaskmanTimeEntrySumHoursPatch'
}

# Check runtime_compat.rb exists and read it
compat_file = '/usr/src/redmine/config/initializers/runtime_compat.rb'
runtime_content = nil

if File.exist?(compat_file)
  runtime_content = File.read(compat_file)
  puts "Found runtime_compat.rb at: #{compat_file}"
else
  puts "Warning: runtime_compat.rb not found at: #{compat_file}"
end

patches.each do |toggle_name, module_name|
  toggle_pattern = /#{toggle_name.downcase}_patch_enabled\s*=\s*TaskmanRuntimeCompat\.patch_enabled/i

  # Check module definition exists
  module_pattern = /module\s+#{module_name}/

  toggle_exists = runtime_content && toggle_pattern.match(runtime_content)
  module_exists = runtime_content && module_pattern.match(runtime_content)
  module_defined = begin
    defined?(Kernel) && eval("defined?(#{module_name})") == 'constant'
  rescue StandardError
    false
  end

  # Check both toggle and module exist
  check("Toggle #{toggle_name} defined in runtime_compat.rb", toggle_exists)
  if toggle_exists
    pass_count += 1
    results << { name: "Toggle: #{toggle_name}", passed: true }
  else
    fail_count += 1
    results << { name: "Toggle: #{toggle_name}", passed: false }
  end

  check("Module #{module_name} defined in runtime_compat.rb", module_exists || module_defined)
  if module_exists || module_defined
    pass_count += 1
    results << { name: "Module: #{module_name}", passed: true }
  else
    fail_count += 1
    results << { name: "Module: #{module_name}", passed: false }
  end
end

puts

# ============================================================================
# Section 4: AgileQuery Patches
# ============================================================================
puts '=' * 60
puts 'Section 4: AgileQuery Patches'
puts '=' * 60

if defined?(AgileQuery)
  # Check if TaskmanAgileQueryPerfPatch is prepended
  prepended = begin
    AgileQuery.ancestors.include?(TaskmanAgileQueryPerfPatch)
  rescue StandardError
    false
  end
  passed, = check('TaskmanAgileQueryPerfPatch is prepended to AgileQuery', prepended)
  passed ? pass_count += 1 : fail_count += 1
  results << { name: 'AgileQuery prepended with TaskmanAgileQueryPerfPatch', passed: prepended }

  # Test board_issue_statuses method doesn't crash
  begin
    # Create a mock query to test the method
    if defined?(AgileQuery) && AgileQuery.method_defined?(:board_issue_statuses)
      # We can't easily test without fixtures, but verify method exists
      passed, = check('board_issue_statuses method exists', true)
      pass_count += 1
      results << { name: 'board_issue_statuses method exists', passed: true }
    else
      passed, = check('board_issue_statuses method exists', false)
      fail_count += 1
      results << { name: 'board_issue_statuses method exists', passed: false }
    end
  rescue StandardError => e
    passed, = check('board_issue_statuses method works', false, e.message)
    fail_count += 1
    results << { name: 'board_issue_statuses method works', passed: false }
  end
else
  puts 'SKIP: AgileQuery not defined'
end

puts

# ============================================================================
# Section 5: Database Seed Data
# ============================================================================
puts '=' * 60
puts 'Section 5: Database Seed Data'
puts '=' * 60

# Only check if Rails and models are available
if defined?(ActiveRecord) && ActiveRecord::Base.connected?
  models_counts = {
    'Issue' => Issue,
    'Project' => Project,
    'Member' => Member
  }

  optional_models = {
    'AgileSprint' => defined?(AgileSprint) ? AgileSprint : nil,
    'ResourceBooking' => defined?(ResourceBooking) ? ResourceBooking : nil,
    'HelpdeskTicket' => defined?(HelpdeskTicket) ? HelpdeskTicket : nil,
    'Contact' => defined?(Contact) ? Contact : nil
  }

  models_counts.each do |name, model|
    count = model.count
    passed, = check("#{name}.count > 0", count > 0, "count=#{count}")
    passed ? pass_count += 1 : fail_count += 1
    results << { name: "Seed data: #{name} (#{count})", passed: count > 0 }
  rescue StandardError => e
    passed, = check("#{name} accessible", false, e.message)
    fail_count += 1
    results << { name: "Seed data: #{name}", passed: false }
  end

  optional_models.each do |name, model|
    next unless model

    begin
      count = model.count
      if count > 0
        passed, = check("#{name}.count > 0", true, "count=#{count}")
        pass_count += 1
        results << { name: "Seed data: #{name} (#{count})", passed: true }
      else
        passed, = check("#{name}.count > 0", false, 'count=0 - optional model may not have data')
        fail_count += 1
        results << { name: "Seed data: #{name} (empty)", passed: false }
      end
    rescue StandardError => e
      passed, = check("#{name} accessible", false, e.message)
      fail_count += 1
      results << { name: "Seed data: #{name}", passed: false }
    end
  end
else
  puts 'SKIP: Database not connected - cannot verify seed data'
end

puts

# ============================================================================
# Section 6: View Override Files
# ============================================================================
puts '=' * 60
puts 'Section 6: View Override Files'
puts '=' * 60

plugin_views = {
  '/usr/src/redmine/plugins/redmine_eea_patches/app/views/projects/_helpdesk_tickets.html.erb' => 'projects/_helpdesk_tickets.html.erb',
  '/usr/src/redmine/plugins/redmine_eea_patches/app/views/context_menus/_sprints.html.erb' => 'context_menus/_sprints.html.erb',
  '/usr/src/redmine/plugins/redmine_eea_patches/init.rb' => 'init.rb'
}

plugin_views.each do |path, name|
  exists = File.exist?(path)
  passed, = check("View override exists: #{name}", exists)
  passed ? pass_count += 1 : fail_count += 1
  results << { name: "View override: #{name}", passed: exists }
end

puts
puts '=' * 60
puts 'SUMMARY'
puts '=' * 60
puts "Total: #{pass_count + fail_count} checks"
puts "Passed: #{pass_count}"
puts "Failed: #{fail_count}"
puts '=' * 60

if fail_count > 0
  puts 'RESULT: VALIDATION FAILED'
  exit 1
else
  puts 'RESULT: ALL VALIDATIONS PASSED'
  exit 0
end

# frozen_string_literal: true

# db/seeds/time_entries_perf_test.rb
#
# Seed data for time_entries N+1 query testing
# Run with: rails runner db/seeds/time_entries_perf_test.rb
#
# Reproduces the N+1 issues seen on taskman.02pre:
# 1. custom_values per TimeEntry (25 queries for 25 entries)
# 2. enabled_modules per Project (11 queries for 11 projects)
# 3. Separate SUM query for hours total

puts "Creating time entries performance test data..."

# ============================================================================
# Setup: Ensure we have base data
# ============================================================================
unless Project.any?
  puts "ERROR: No projects found. Run standard Redmine seeds first."
  exit 1
end

unless TimeEntry.table_exists?
  puts "ERROR: TimeEntry table doesn't exist."
  exit 1
end

# ============================================================================
# Create TimeEntryCustomField if needed
# ============================================================================
time_entry_cf = TimeEntryCustomField.find_or_create_by!(
  name: "Test Time CF",
  field_format: "string"
) do |cf|
  cf.is_filter = true
  cf.position = 1
end

puts "Using TimeEntryCustomField: #{time_entry_cf.name} (id=#{time_entry_cf.id})"

# ============================================================================
# Create multiple projects with time tracking enabled
# ============================================================================
projects = Project.where(status: [1, 5]).limit(15).to_a
if projects.size < 10
  puts "Creating additional test projects..."
  10.times do |i|
    p = Project.find_or_create_by!(
      identifier: "time_entry_perf_#{i + 1}"
    ) do |proj|
      proj.name = "Time Entry Perf Test #{i + 1}"
      proj.is_public = false
    end
    projects << p
  end
end

puts "Using #{projects.size} projects"

# Enable time_tracking module on all test projects
projects.each do |project|
  unless project.module_enabled?(:time_tracking)
    project.enabled_modules.create!(name: 'time_tracking')
  end
end

# ============================================================================
# Create time entries with custom values
# ============================================================================
activities = TimeEntryActivity.all.to_a
users = User.active.where(type: 'User').limit(20).to_a
issues = Issue.where(project_id: projects.map(&:id)).limit(100).to_a

puts "Creating 50 time entries with custom values..."

time_entries_created = 0
50.times do |i|
  project = projects.sample
  issue = issues.find { |iss| iss.project_id == project.id } || project.issues.sample
  user = users.sample
  activity = activities.sample

  te = TimeEntry.find_or_create_by!(
    project_id: project.id,
    issue_id: issue&.id,
    user_id: user.id,
    activity_id: activity&.id,
    spent_on: Date.today - rand(60)
  ) do |t|
    t.hours = rand(0.5..8.0)
    t.comments = "Perf test time entry #{i + 1}"
  end

  # Add custom value for our test CF
  unless te.custom_values.where(custom_field_id: time_entry_cf.id).exists?
    te.custom_values.create!(
      custom_field_id: time_entry_cf.id,
      value: "Test value #{i + 1}"
    )
  end

  time_entries_created += 1
  print "." if (i + 1) % 10 == 0
end

puts "\nCreated #{time_entries_created} time entries"

# ============================================================================
# Summary
# ============================================================================
puts "\n" + "=" * 60
puts "Time Entry Performance Test Data Summary"
puts "=" * 60
puts "  Time Entries: #{TimeEntry.count}"
puts "  Projects: #{projects.size}"
puts "  Issues used: #{issues.size}"
puts "  Users: #{users.size}"
puts "  TimeEntryCustomField: #{time_entry_cf.name} (id=#{time_entry_cf.id})"
puts "\nThis data exercises:"
puts "  - N+1: custom_values per TimeEntry (no preload)"
puts "  - N+1: enabled_modules per Project (no preload)"
puts "  - Separate SUM query for total hours"
puts ""
puts "To test, visit: /time_entries (as a user with limited access)"
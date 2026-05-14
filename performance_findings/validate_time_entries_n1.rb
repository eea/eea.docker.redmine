# frozen_string_literal: true

# Validate time_entries N+1 fixes by measuring query patterns
# Run with: bundle exec rails runner performance_findings/validate_time_entries_n1.rb

require 'benchmark'
require 'active_support/core_ext/objecttry'

OUTPUT_DIR = '/tmp/perf_test_results'
FileUtils.mkdir_p(OUTPUT_DIR)

puts "=" * 70
puts "Time Entries N+1 Query Validation"
puts "=" * 70
puts "Started at: #{Time.now.utc}"
puts ""

results = []

# ============================================================================
# Setup: Create test data if needed
# ============================================================================
puts "[1/4] Setting up test data..."
puts "-" * 50

# Load seed to create data
load Rails.root.join('db/seeds/time_entries_perf_test.rb')

time_entries = TimeEntry.includes(:project, :user, :activity).limit(50).to_a
projects = time_entries.map(&:project).compact.uniq
issues = time_entries.map(&:issue).compact.uniq

puts "Test data: #{time_entries.size} time_entries, #{projects.size} projects, #{issues.size} issues"
puts ""

# ============================================================================
# Test 1: custom_values N+1
# ============================================================================
puts "[2/4] Testing custom_values N+1..."
puts "-" * 50

cf_query_count = 0
cf_queries = []

ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
  if payload[:sql] =~ /custom_values/i && payload[:sql] !~ /SELECT.*custom_values.*FROM/i
    cf_query_count += 1
    cf_queries << payload[:sql] if cf_queries.size < 5
  end
end

# Scenario A: Access custom_values WITHOUT preload (triggers N+1)
te = time_entries.first
cf_query_count = 0
Benchmark.realtime { te.custom_values.to_a }
queries_before = cf_query_count

# Scenario B: Preload custom_values
cf_query_count = 0
time_entries_with_cvs = TimeEntry.includes(:custom_values).limit(50).to_a
Benchmark.realtime { time_entries_with_cvs.first.custom_values.to_a }
queries_after_preload = cf_query_count

puts "  Before preload: #{queries_before} queries for custom_values"
puts "  After preload:  #{queries_after_preload} queries for custom_values"
puts "  Improvement:    #{(queries_before.to_f / [queries_after_preload, 1].max).round(1)}x"

results << {
  test: "custom_values N+1",
  queries_before: queries_before,
  queries_after: queries_after_preload,
  status: queries_after_preload < queries_before ? "IMPROVED" : "NO_CHANGE"
}
puts ""

# ============================================================================
# Test 2: enabled_modules N+1
# ============================================================================
puts "[3/4] Testing enabled_modules N+1..."
puts "-" * 50

module_query_count = 0
module_queries = []

ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
  if payload[:sql] =~ /enabled_modules/i && payload[:sql] !~ /JOIN/i
    module_query_count += 1
    module_queries << payload[:sql] if module_queries.size < 3
  end
end

# Scenario A: module_enabled? WITHOUT preload (triggers N+1 per project)
module_query_count = 0
Benchmark.realtime { projects.map { |p| p.module_enabled?(:time_tracking) } }
queries_before_modules = module_query_count

# Scenario B: Batch preload enabled_modules
module_query_count = 0
project_ids = projects.map(&:id)
preloaded_modules = EnabledModule.where(project_id: project_ids).to_a.group_by(&:project_id)
Benchmark.realtime do
  projects.map { |p| preloaded_modules[p.id] && preloaded_modules[p.id].any? { |m| m.name == 'time_tracking' } }
end
queries_after_modules = module_query_count

puts "  Before preload: #{queries_before_modules} queries for enabled_modules"
puts "  After preload:  #{queries_after_modules} queries for enabled_modules"
puts "  Improvement:    #{(queries_before_modules.to_f / [queries_after_modules, 1].max).round(1)}x"

results << {
  test: "enabled_modules N+1",
  queries_before: queries_before_modules,
  queries_after: queries_after_modules,
  status: queries_after_modules < queries_before_modules ? "IMPROVED" : "NO_CHANGE"
}
puts ""

# ============================================================================
# Test 3: SUM query combination
# ============================================================================
puts "[4/4] Testing SUM hours combination..."
puts "-" * 50

# Current: Separate SUM query
sum_query_count = 0
ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
  sum_query_count += 1 if payload[:sql] =~ /SUM.*hours/i
end

# Current behavior: SUM runs separately
scope = TimeEntry.where(id: time_entries.map(&:id))
total_hours_separate = nil
sum_query_count = 0
t_separate = Benchmark.realtime do
  entries = scope.to_a
  total_hours_separate = entries.sum(&:hours)
end
separate_queries = sum_query_count

# Optimized: Single query with ALL
total_hours_combined = nil
sum_query_count = 0
t_combined = Benchmark.realtime do
  total_hours_combined = scope.sum(:hours)
end
combined_queries = sum_query_count

puts "  Separate (Ruby sum): #{sprintf('%.3f', t_separate)}s, #{separate_queries} SUM queries"
puts "  Combined (SQL sum):  #{sprintf('%.3f', t_combined)}s, #{combined_queries} SUM queries"
puts "  Speedup:            #{sprintf('%.1f', t_separate / t_combined)}x"

results << {
  test: "SUM hours combination",
  before_ms: (t_separate * 1000).round(1),
  after_ms: (t_combined * 1000).round(1),
  status: t_combined < t_separate ? "IMPROVED" : "NO_CHANGE"
}
puts ""

# ============================================================================
# Summary
# ============================================================================
puts "=" * 70
puts "TIME ENTRIES N+1 VALIDATION RESULTS"
puts "=" * 70
puts ""
puts sprintf("%-40s %15s %15s %s", "TEST", "BEFORE", "AFTER", "STATUS")
puts "-" * 70

results.each do |r|
  if r[:queries_before]
    puts sprintf("%-40s %15d %15d %s", r[:test], r[:queries_before], r[:queries_after], r[:status])
  else
    puts sprintf("%-40s %15.1fms %15.1fms %s", r[:test], r[:before_ms], r[:after_ms], r[:status])
  end
end

puts "-" * 70
improved = results.count { |r| r[:status] == "IMPROVED" }
total = results.size
puts "Tests improved: #{improved}/#{total}"
puts ""
puts "Completed at: #{Time.now.utc}"

# Save results
output_file = File.join(OUTPUT_DIR, "time_entries_n1_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json")
File.write(output_file, results.to_json)
puts "Results saved to: #{output_file}"
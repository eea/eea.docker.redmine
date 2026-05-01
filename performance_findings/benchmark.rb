#!/usr/bin/env ruby
# frozen_string_literal: true

# Performance Benchmark Script
# Compares slow vs fast queries for Redmine Helpdesk and AGILE_QUERY patch
#
# Usage:
#   docker compose -f test/docker-compose.yml exec -T redmine bundle exec rails runner performance_findings/benchmark.rb
#
# Or copy and paste into rails console:
#   bundle exec rails console
#   load 'performance_findings/benchmark.rb'

require "benchmark"

PROJECT_ID = 161  # nanyt - EEA enquiries

def log(msg)
  puts msg
end

def run_agile_benchmark
  return unless defined?(AgileQuery)
  return unless Object.const_defined?(:Issue)
  return unless Issue.table_exists?
  return unless IssueStatus.table_exists?

  log ""
  log "=" * 70
  log "AGILE_QUERY Patch Benchmark"
  log "=" * 70
  log ""

  # Check if patch is enabled
  patch_enabled = ENV.fetch("TASKMAN_PATCH_AGILE_QUERY", "0") == "1"
  log "AGILE_QUERY patch enabled: #{patch_enabled}"
  log ""

  # Create a mock board query to test the optimization
  log "Benchmark: board_issue_statuses (via AgileQuery)"
  log "-" * 70

  # Get a project with issues
  project = Project.find_by(id: PROJECT_ID) || Project.first
  return log "No project found for benchmark" unless project

  # Create an issue scope with a tracker that has workflows
  issue_scope = Issue.where(project_id: project.id)
  tracker = Tracker.first
  return log "No tracker available for benchmark" unless tracker

  # Benchmark original method if patch not enabled
  if patch_enabled
    log "Using optimized board_issue_statuses query"
    query_time = Benchmark.measure do
      # Simulate what the patch does
      tracker_ids = issue_scope.unscope(:select, :order)
                             .where.not(tracker_id: nil)
                             .distinct
                             .pluck(:tracker_id)

      unless tracker_ids.empty?
        status_ids = WorkflowTransition.where(tracker_id: tracker_ids)
                                       .distinct
                                       .pluck(:old_status_id, :new_status_id)
                                       .flatten
                                       .uniq
        result = IssueStatus.where(id: status_ids)
        log "  Result: #{result.count} statuses for #{tracker_ids.count} trackers"
      end
    end
    log "  Time: #{(query_time.real * 1000).round(2)}ms"
  else
    log "Patch not enabled - would use original method"
  end

  log ""
end

def run_explain_queries
  log ""
  log "=" * 70
  log "EXPLAIN Query Analysis"
  log "=" * 70
  log ""

  # Check if HelpdeskTicket exists
  if !Object.const_defined?(:HelpdeskTicket) || !HelpdeskTicket.table_exists?
    log "HelpdeskTicket not available - skipping EXPLAIN"
    return
  end

  queries = []

  # Slow query EXPLAIN
  queries << {
    name: "Slow Query (includes with LEFT JOIN)",
    sql: "SELECT `helpdesk_tickets`.* FROM `helpdesk_tickets` " \
         "LEFT OUTER JOIN `issues` ON `issues`.`id` = `helpdesk_tickets`.`issue_id` " \
         "LEFT OUTER JOIN `projects` ON `projects`.`id` = `issues`.`project_id` " \
         "WHERE `projects`.`id` = #{PROJECT_ID}"
  }

  # Fast query EXPLAIN
  queries << {
    name: "Fast Query (COUNT with INNER JOIN)",
    sql: "SELECT COUNT(*) FROM `helpdesk_tickets` " \
         "INNER JOIN `issues` ON `issues`.`id` = `helpdesk_tickets`.`issue_id` " \
         "WHERE `issues`.`project_id` = #{PROJECT_ID}"
  }

  # Customer count query
  queries << {
    name: "Customer Count (DISTINCT)",
    sql: "SELECT COUNT(DISTINCT `helpdesk_tickets`.`contact_id`) FROM `helpdesk_tickets` " \
         "INNER JOIN `issues` ON `issues`.`id` = `helpdesk_tickets`.`issue_id` " \
         "WHERE `issues`.`project_id` = #{PROJECT_ID} AND `helpdesk_tickets`.`contact_id` IS NOT NULL"
  }

  queries.each do |q|
    log "Query: #{q[:name]}"
    log "-" * 70
    log q[:sql]
    log "-" * 70

    begin
      result = ActiveRecord::Base.connection.execute("EXPLAIN #{q[:sql]")
      result.each do |row|
        log row.join(" | ")
      end
    rescue => e
      log "  ERROR: #{e.message}"
    end
    log ""
  end
end

log "=" * 70
log "Redmine Helpdesk Performance Benchmark"
log "Project: nanyt (ID: #{PROJECT_ID})"
log "=" * 70
log ""

# Verify project exists
project = Project.find_by(id: PROJECT_ID)
unless project
  log "ERROR: Project #{PROJECT_ID} not found"
  exit 1
end

log "Project: #{project.name}"
log "Public: #{project.is_public}"
log ""

# Gather statistics
if Object.const_defined?(:HelpdeskTicket) && HelpdeskTicket.table_exists?
  log "Gathering statistics..."
  issue_count = Issue.where(project_id: PROJECT_ID).count
  ticket_count = HelpdeskTicket.joins(:issue).where(issues: { project_id: PROJECT_ID }).count
  customer_count = HelpdeskTicket.joins(:issue).where(issues: { project_id: PROJECT_ID })
                                  .where.not(contact_id: nil).distinct.count(:contact_id)

  log "  Total Issues: #{issue_count}"
  log "  Helpdesk Tickets: #{ticket_count}"
  log "  Distinct Customers: #{customer_count}"
  log ""
end

# Benchmark slow query (with timeout protection)
if Object.const_defined?(:HelpdeskTicket) && HelpdeskTicket.table_exists?
  log "Benchmark 1: Slow Query (Original)"
  log "Query: HelpdeskTicket.includes(:issue => [:project]).where(:projects => {:id => #{PROJECT_ID}}).count"
  log "Note: This may timeout. Press Ctrl+C to skip..."
  log "-" * 70

  slow_time = nil
  begin
    # Set a timeout to prevent hanging indefinitely
    Timeout.timeout(30) do
      slow_time = Benchmark.measure do
        tickets = HelpdeskTicket.includes(issue: [:project]).where(projects: { id: PROJECT_ID })
        count = tickets.count
        log "  Result: #{count} tickets"
      end
    end
    log "  Time: #{slow_time.real.round(2)}s"
  rescue Timeout::Error
    log "  TIMEOUT after 30 seconds (this demonstrates the problem)"
    slow_time = nil
  rescue => e
    log "  ERROR: #{e.message}"
    slow_time = nil
  end
  log ""

  # Benchmark fast queries
  log "Benchmark 2: Fast Query (Optimized Ticket Count)"
  log "Query: HelpdeskTicket.joins(:issue).where(:issues => { project_id: #{PROJECT_ID} }).count"
  log "-" * 70

  fast_ticket_time = Benchmark.measure do
    count = HelpdeskTicket.joins(:issue).where(issues: { project_id: PROJECT_ID }).count
    log "  Result: #{count} tickets"
  end
  log "  Time: #{(fast_ticket_time.real * 1000).round(2)}ms"
  log ""

  log "Benchmark 3: Fast Query (Optimized Customer Count)"
  log "Query: HelpdeskTicket.joins(:issue).where(...).where.not(:contact_id => nil).distinct.count(:contact_id)"
  log "-" * 70

  fast_customer_time = Benchmark.measure do
    count = HelpdeskTicket.joins(:issue).where(issues: { project_id: PROJECT_ID })
                          .where.not(contact_id: nil).distinct.count(:contact_id)
    log "  Result: #{count} customers"
  end
  log "  Time: #{(fast_customer_time.real * 1000).round(2)}ms"
  log ""

  # Summary
  log "=" * 70
  log "SUMMARY"
  log "=" * 70

  if slow_time
    improvement = ((slow_time.real / fast_ticket_time.real)).round(0)
    log "Slow query: #{slow_time.real.round(2)}s"
    log "Fast query: #{(fast_ticket_time.real * 1000).round(2)}ms"
    log "Improvement: #{improvement}x faster"
  else
    log "Slow query: TIMEOUT (>30s)"
    log "Fast query: #{(fast_ticket_time.real * 1000).round(2)}ms"
    log "Improvement: >99% faster (timeout vs instant)"
  end
  log ""
end

# Run AGILE_QUERY benchmark
run_agile_benchmark

# Run EXPLAIN analysis
run_explain_queries

# SQL output for analysis
log "=" * 70
log "SQL QUERIES FOR MANUAL ANALYSIS"
log "=" * 70
log ""

if Object.const_defined?(:HelpdeskTicket) && HelpdeskTicket.table_exists?
  log "Slow Query SQL:"
  log "-" * 70
  slow_relation = HelpdeskTicket.includes(issue: [:project]).where(projects: { id: PROJECT_ID })
  log slow_relation.to_sql
  log ""

  log "Fast Query SQL (Ticket Count):"
  log "-" * 70
  fast_relation = HelpdeskTicket.joins(:issue).where(issues: { project_id: PROJECT_ID })
  log fast_relation.to_sql
  log ""

  log "Fast Query SQL (Customer Count):"
  log "-" * 70
  log "SELECT COUNT(DISTINCT helpdesk_tickets.contact_id) FROM helpdesk_tickets"
  log "INNER JOIN issues ON issues.id = helpdesk_tickets.issue_id"
  log "WHERE issues.project_id = #{PROJECT_ID} AND helpdesk_tickets.contact_id IS NOT NULL"
  log ""
end

log "=" * 70
log "RECOMMENDATION: Apply the fix to replace slow queries with fast ones"
log "=" * 70
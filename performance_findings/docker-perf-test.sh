#!/bin/bash
# Performance testing script for EEA Redmine
# Usage: ./performance_findings/docker-perf-test.sh [compose-file]

set -e

COMPOSE_FILE="${1:-test/docker-compose.yml}"
REDMINE_SERVICE="redmine"
MYSQL_SERVICE="mysql"
DB="redmine_test"
MYSQL_USER="redmine"
MYSQL_PASS="password"

echo "========================================"
echo "EEA Redmine Performance Test Suite"
echo "Compose: $COMPOSE_FILE"
echo "========================================"
echo ""

# Helper: run mysql query
mysql_query() {
  docker compose -f "$COMPOSE_FILE" exec -T "$MYSQL_SERVICE" \
    mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" "$DB" -e "$1" 2>/dev/null
}

# Helper: run rails command
rails_exec() {
  docker compose -f "$COMPOSE_FILE" exec -T "$REDMINE_SERVICE" \
    bundle exec rails runner "$1" 2>/dev/null
}

echo "1. Checking indexes..."
echo "----------------------------------------"
mysql_query "
SELECT TABLE_NAME, INDEX_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columns
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = '$DB'
  AND TABLE_NAME IN ('issues', 'projects', 'time_entries', 'wiki_pages', 'wiki_links', 'agile_data')
GROUP BY TABLE_NAME, INDEX_NAME
ORDER BY TABLE_NAME, INDEX_NAME;
"

echo ""
echo "2. Checking AGILE_QUERY patch status..."
echo "----------------------------------------"
rails_exec "
patch = ENV.fetch('TASKMAN_PATCH_AGILE_QUERY', '0')
puts \"AGILE_QUERY patch enabled: #{patch == '1'}\"
puts \"AgileQuery defined: #{defined?(AgileQuery) ? 'yes' : 'no'}\"
if defined?(AgileQuery)
  puts \"Patch applied: #{AgileQuery.ancestors.include?(TaskmanAgileQueryPerfPatch) rescue 'unknown'}\"
end
"

echo ""
echo "3. Checking helpdesk ticket query performance..."
echo "----------------------------------------"
rails_exec "
require 'benchmark'
if defined?(HelpdeskTicket) && HelpdeskTicket.table_exists?
  project = Project.first
  if project
    t = Benchmark.measure { HelpdeskTicket.joins(:issue).where(issues: { project_id: project.id }).count }
    puts \"Fast ticket count: #{(t.real * 1000).round(2)}ms\"
    t2 = Benchmark.measure { HelpdeskTicket.joins(:issue).where(issues: { project_id: project.id }).where.not(contact_id: nil).distinct.count(:contact_id) }
    puts \"Fast customer count: #{(t2.real * 1000).round(2)}ms\"
  else
    puts 'No project found'
  end
else
  puts 'HelpdeskTicket not available'
end
"

echo ""
echo "4. Checking slow query EXPLAIN..."
echo "----------------------------------------"
mysql_query "
EXPLAIN SELECT COUNT(*) FROM helpdesk_tickets
INNER JOIN issues ON issues.id = helpdesk_tickets.issue_id
WHERE issues.project_id = 1;
" 2>/dev/null || echo "  (helpdesk_tickets table not available)"

echo ""
echo "5. Checking agile_data composite index..."
echo "----------------------------------------"
mysql_query "
SELECT INDEX_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columns
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = '$DB' AND TABLE_NAME = 'agile_data'
GROUP BY INDEX_NAME;
" 2>/dev/null || echo "  (agile_data table not available)"

echo ""
echo "========================================"
echo "Performance test complete"
echo "========================================"
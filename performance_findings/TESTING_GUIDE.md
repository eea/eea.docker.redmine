# Testing Guide: Redmine Performance Fixes

## Prerequisites

- Docker and docker compose installed
- Access to test environment via `test/docker-compose.yml`
- For production: kubectl access to 02pre/taskman cluster

---

## Quick Commands Reference

```bash
# Run the benchmark
docker compose -f test/docker-compose.yml exec -T redmine bundle exec rake test:performance

# Test specific query with EXPLAIN
docker compose -f test/docker-compose.yml exec -T mysql mysql -uredmine -ppassword -e "EXPLAIN SELECT * FROM redmine_test.issues WHERE project_id=1 AND status_id=1;"

# Check if AGILE_QUERY patch is running
docker compose -f test/docker-compose.yml exec -T redmine grep "AGILE_QUERY" log/production.log
```

---

## Test 1: Helpdesk Performance Fix

### Running the Performance Test

```bash
docker compose -f test/docker-compose.yml exec -T redmine bundle exec rails test \
  plugins/redmine_eea_patches/test/unit/patches/helpdesk_performance_test.rb -v
```

Expected output:
- All tests pass
- Query times < 1 second for ticket and customer counts

### Manual EXPLAIN Analysis

```bash
# Analyze slow query (LEFT JOIN)
docker compose -f test/docker-compose.yml exec -T mysql mysql -uredmine -ppassword redmine_test -e "
EXPLAIN SELECT helpdesk_tickets.* FROM helpdesk_tickets
LEFT OUTER JOIN issues ON issues.id = helpdesk_tickets.issue_id
LEFT OUTER JOIN projects ON projects.id = issues.project_id
WHERE projects.id = 1;
"

# Analyze fast query (INNER JOIN with COUNT)
docker compose -f test/docker-compose.yml exec -T mysql mysql -uredmine -ppassword redmine_test -e "
EXPLAIN SELECT COUNT(*) FROM helpdesk_tickets
INNER JOIN issues ON issues.id = helpdesk_tickets.issue_id
WHERE issues.project_id = 1;
"
```

### Verify Index Usage

Check that `type=ref` appears in EXPLAIN output indicating index usage:
- `issues_project_id` should be used for `issues.project_id`
- `index_helpdesk_tickets_on_issue_id_and_contact_id` should be used for the join

---

## Test 2: AGILE_QUERY Patch

### What the Patch Does

The `AGILE_QUERY` patch optimizes `AgileQuery#board_issue_statuses` by:
1. Fetching tracker IDs separately instead of joining through issue_scope
2. Querying workflows directly with tracker IDs
3. Avoiding expensive joins through tracker/project to workflows

### Enable/Disable the Patch

```bash
# Enable (default in test environment)
TASKMAN_PATCH_AGILE_QUERY=1 docker compose -f test/docker-compose.yml up -d

# Disable
TASKMAN_PATCH_AGILE_QUERY=0 docker compose -f test/docker-compose.yml up -d
```

### Verify Patch is Running

```bash
# Check Rails logs for patch initialization
docker compose -f test/docker-compose.yml exec -T redmine grep "AGILE_QUERY" log/production.log

# Should see: [runtime_compat] patch=AGILE_QUERY enabled=true
```

### Test AGILE_QUERY Performance

```bash
# Run benchmark with AGILE_QUERY enabled
docker compose -f test/docker-compose.yml exec -T redmine bundle exec rails runner \
  performance_findings/benchmark.rb 2>&1 | grep -A20 "AGILE_QUERY"
```

### Manual Query Test

```bash
# Test the original slow query pattern
docker compose -f test/docker-compose.yml exec -T mysql mysql -uredmine -ppassword redmine_test -e "
EXPLAIN SELECT DISTINCT tracker_id FROM issues WHERE project_id = 1;
"

# Test the optimized workflow query
docker compose -f test/docker-compose.yml exec -T mysql mysql -uredmine -ppassword redmine_test -e "
EXPLAIN SELECT DISTINCT old_status_id, new_status_id FROM workflow_transitions
WHERE tracker_id IN (1, 2, 3);
"
```

---

## Test 3: Running Full Performance Suite

```bash
# Build and start test environment
docker compose -f test/docker-compose.yml up -d --build

# Wait for services to be ready
docker compose -f test/docker-compose.yml exec -T redmine rake db:wait

# Run helpdesk performance test
docker compose -f test/docker-compose.yml exec -T redmine bundle exec rails test \
  plugins/redmine_eea_patches/test/unit/patches/helpdesk_performance_test.rb -v

# Run the benchmark script
docker compose -f test/docker-compose.yml exec -T redmine bundle exec rails runner \
  performance_findings/benchmark.rb

# Run all unit tests for the plugin
docker compose -f test/docker-compose.yml exec -T redmine bundle exec rails test \
  plugins/redmine_eea_patches/test/unit/patches/ -v
```

---

## Test 4: Verify Index Usage

### Check Existing Indexes

```bash
docker compose -f test/docker-compose.yml exec -T mysql mysql -uredmine -ppassword redmine_test -e "
SHOW INDEX FROM issues;
SHOW INDEX FROM helpdesk_tickets;
SHOW INDEX FROM workflow_transitions;
"
```

### EXPLAIN Query Analysis

When running EXPLAIN, look for:
- `type=ref` - index is being used for lookups
- `type=range` - index is being used for range scans
- `Using index` - covering index is being used
- `Using filesort` - temporary table needed (bad)

### Example Good Output (Fast Query)

```
+----+-------------+---------------------+-------------+-------------------+-------------+---------+--------------------------+------+----------+-------------+
| id | select_type | table               | type        | possible_keys     | key         | key_len | ref                      | rows | filtered | Extra       |
+----+-------------+---------------------+-------------+-------------------+-------------+---------+--------------------------+------+----------+-------------+
|  1 | SIMPLE      | helpdesk_tickets    | index       | PRIMARY           | PRIMARY    | 8       | NULL                     |   10 |   100.00 | Using index |
|  1 | SIMPLE      | issues              | eq_ref      | PRIMARY,idx_issue | PRIMARY    | 4       | helpdesk_tickets.issue_id|    1 |   100.00 | Using where |
+----+-------------+---------------------+-------------+-------------------+-------------+---------+--------------------------+------+----------+-------------+
```

### Example Bad Output (Slow Query)

```
+----+-------------+-------------+------+-------------+------+---------+------+----------+------------------------+
| id | select_type | table       | type | possible_keys | key  | key_len | ref  | rows     | Extra                  |
+----+-------------+-------------+------+-------------+------+---------+------+----------+------------------------+
|  1 | SIMPLE      | projects    | ALL  | PRIMARY       | NULL | NULL    | NULL |    10000 | Using where            |
|  1 | SIMPLE      | issues     | ref  | idx_issue     | idx_issue | 4   | projects.id | 500              | Using index           |
|  1 | SIMPLE      | helpdesk   | ALL  | idx_helpdesk  | NULL | NULL    | NULL |    50000 | Using where; Using join|
+----+-------------+-------------+------+-------------+------+---------+------+----------+------------------------+
```

---

## Test 5: Production Environment Testing

### Kubernetes Deployment

```bash
# Check current patch status
kubectl exec taskman-redmine-dpl-<pod> -n taskman -c taskman-redmine -- \
  grep "AGILE_QUERY" /usr/src/redmine/log/production.log | tail -5

# Check if patch is enabled in environment
kubectl exec taskman-redmine-dpl-<pod> -n taskman -c taskman-redmine -- \
  env | grep TASKMAN_PATCH
```

### Performance Monitoring

```bash
# Tail Rails logs for slow queries
kubectl exec taskman-redmine-dpl-<pod> -n taskman -c taskman-redmine -- \
  tail -f /usr/src/redmine/log/production.log | grep -E "Completed|ActiveRecord"

# Check MySQL slow query log
kubectl exec taskman-mysql-ss-0 -n taskman -- \
  mysql -u root -p -e "SHOW VARIABLES LIKE 'slow_query_log%';"
```

---

## Rollback Instructions

If issues are encountered:

### Disable AGILE_QUERY Patch

```bash
# Via environment variable
TASKMAN_PATCH_AGILE_QUERY=0 docker compose -f test/docker-compose.yml up -d

# Or in Kubernetes
kubectl set env deployment/taskman-redmine TASKMAN_PATCH_AGILE_QUERY=0 -n taskman
```

### Disable Helpdesk Patch

The helpdesk fix is in the view partial. To rollback:
1. Restore the original `redmine_contacts_helpdesk` plugin view
2. Restart the pod

---

## Success Criteria

### Helpdesk Performance
- ✅ Ticket count query: < 100ms
- ✅ Customer count query: < 100ms
- ✅ EXPLAIN shows index usage (type=ref or Using index)
- ✅ No LEFT OUTER JOIN in fast path

### AGILE_QUERY Patch
- ✅ Patch logs show `patch=AGILE_QUERY enabled=true`
- ✅ `board_issue_statuses` returns same results as original
- ✅ EXPLAIN shows optimized workflow query
- ✅ No fallback errors in logs

### General
- ✅ All unit tests pass
- ✅ No regression in other functionality
- ✅ Logs are clean (no errors/warnings from patches)

---

## Sign-Off

| Tester | Date | Result | Notes |
|--------|------|--------|-------|
| | | | |
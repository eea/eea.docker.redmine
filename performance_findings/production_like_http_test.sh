#!/usr/bin/env bash
set -euo pipefail

# Production-like HTTP benchmark for Redmine pages.
#
# Requirements:
# - kubectl context with access to taskman-test namespace
# - python3 available locally
#
# Usage:
#   bash performance_findings/production_like_http_test.sh
#
# Optional env vars:
#   NAMESPACE=taskman-test
#   DEPLOYMENT=taskman-local-redmine-dpl
#   LOCAL_PORT=9292
#   WARMUP_RUNS=2
#   MEASURE_RUNS=10
#   CONCURRENCY=1
#   BENCH_LOGIN=perfbench
#   BENCH_PASSWORD=PerfBench!123456
#   RUN_SETUP=0 (skip rails runner user setup)
#   BENCH_PROJECT_IDENTIFIER=perf_intensive_test
#   ENDPOINTS_CSV="/projects/perf_intensive_test/issues,/projects/perf_intensive_test,/projects/perf_intensive_test/time_entries,/projects/perf_intensive_test/activity"

NAMESPACE="${NAMESPACE:-taskman-test}"
DEPLOYMENT="${DEPLOYMENT:-taskman-local-redmine-dpl}"
LOCAL_PORT="${LOCAL_PORT:-9292}"
WARMUP_RUNS="${WARMUP_RUNS:-2}"
MEASURE_RUNS="${MEASURE_RUNS:-10}"
CONCURRENCY="${CONCURRENCY:-1}"
BENCH_LOGIN="${BENCH_LOGIN:-perfbench}"
BENCH_PASSWORD="${BENCH_PASSWORD:-PerfBench!123456}"
RUN_SETUP="${RUN_SETUP:-0}"
BENCH_PROJECT_IDENTIFIER="${BENCH_PROJECT_IDENTIFIER:-perf_intensive_test}"
ENDPOINTS_CSV="${ENDPOINTS_CSV:-}"

WORKDIR="$(mktemp -d)"
COOKIE_JAR="$WORKDIR/cookies.txt"
RESULTS_CSV="$WORKDIR/results.csv"

cleanup() {
  if [[ -n "${PF_PID:-}" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo "[1/6] Setup benchmark user in pod..."
POD="$(kubectl get pods -n "$NAMESPACE" | grep redmine-dpl | grep Running | awk '{print $1}' | head -1)"
if [[ "$RUN_SETUP" == "1" ]]; then
  kubectl exec -n "$NAMESPACE" "$POD" -- mkdir -p /usr/src/redmine/performance_findings >/dev/null
  kubectl cp "performance_findings/setup_benchmark_user.rb" "$NAMESPACE/$POD:/usr/src/redmine/performance_findings/setup_benchmark_user.rb" >/dev/null
  kubectl exec -n "$NAMESPACE" "$POD" -- bash -lc "cd /usr/src/redmine && BENCH_LOGIN='$BENCH_LOGIN' BENCH_PASSWORD='$BENCH_PASSWORD' RAILS_ENV=production bundle exec rails runner performance_findings/setup_benchmark_user.rb"
else
  echo "Skipping setup runner (RUN_SETUP=$RUN_SETUP); using existing BENCH_LOGIN=$BENCH_LOGIN"
fi

echo "[2/6] Port-forward ${LOCAL_PORT}->3000..."
lsof -i ":$LOCAL_PORT" | awk 'NR>1 {print $2}' | xargs kill -9 >/dev/null 2>&1 || true
kubectl port-forward --address 127.0.0.1 -n "$NAMESPACE" "deployment/$DEPLOYMENT" "$LOCAL_PORT:3000" >"$WORKDIR/pf.log" 2>&1 &
PF_PID=$!
sleep 3

BASE_URL="http://127.0.0.1:${LOCAL_PORT}"

echo "[3/6] Authenticate benchmark user..."
# Wait for endpoint readiness
ready=0
for _ in {1..10}; do
  if curl -sS --connect-timeout 3 --max-time 5 "$BASE_URL/login" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" != "1" ]]; then
  echo "ERROR: Redmine endpoint not reachable at $BASE_URL/login"
  exit 1
fi

LOGIN_HTML="$(curl -sS --connect-timeout 5 --max-time 20 "$BASE_URL/login" || true)"
TOKEN="$(python3 -c 'import re,sys; html=sys.argv[1]; m=(re.search(r"name=\"authenticity_token\" value=\"([^\"]+)\"", html) or re.search(r"<meta name=\"csrf-token\" content=\"([^\"]+)\"", html)); print(m.group(1) if m else "")' "$LOGIN_HTML")"
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: Could not extract authenticity token from /login"
  echo "First 300 chars of login HTML:"
  printf '%s' "$LOGIN_HTML" | python3 - <<'PY'
import sys
print(sys.stdin.read()[:300])
PY
  exit 1
fi

LOGIN_CODE="$(curl -sS --connect-timeout 5 --max-time 20 -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -X POST "$BASE_URL/login" \
  --data-urlencode "username=$BENCH_LOGIN" \
  --data-urlencode "password=$BENCH_PASSWORD" \
  --data-urlencode "authenticity_token=$TOKEN" \
  --data-urlencode "back_url=/" -o /dev/null -w "%{http_code}" || true)"
if [[ -z "$LOGIN_CODE" || "$LOGIN_CODE" == "000" ]]; then
  echo "ERROR: Login POST failed (no HTTP response)"
  exit 1
fi

if [[ -n "$ENDPOINTS_CSV" ]]; then
  IFS=',' read -r -a ENDPOINTS <<< "$ENDPOINTS_CSV"
else
  ENDPOINTS=(
    "/projects/${BENCH_PROJECT_IDENTIFIER}/issues"
    "/projects/${BENCH_PROJECT_IDENTIFIER}"
    "/projects/${BENCH_PROJECT_IDENTIFIER}/time_entries"
    "/projects/${BENCH_PROJECT_IDENTIFIER}/activity"
  )
fi

echo "Benchmark endpoints: ${ENDPOINTS[*]}"
echo "[4/6] Warmup runs..."
for ep in "${ENDPOINTS[@]}"; do
  for ((i=1;i<=WARMUP_RUNS;i++)); do
    curl -sS --connect-timeout 5 --max-time 30 -o /dev/null -b "$COOKIE_JAR" "$BASE_URL$ep" || true
  done
done

echo "[5/6] Measured runs (runs=$MEASURE_RUNS, concurrency=$CONCURRENCY)..."
echo "endpoint,run,http_code,time_total" > "$RESULTS_CSV"
for ep in "${ENDPOINTS[@]}"; do
  for ((i=1;i<=MEASURE_RUNS;i++)); do
    line="$(curl -sS --connect-timeout 5 --max-time 30 -o /dev/null -b "$COOKIE_JAR" -w "%{http_code},%{time_total}" "$BASE_URL$ep")"
    echo "${ep},${i},${line}" >> "$RESULTS_CSV"
  done
done

echo "[6/6] Summary"
python3 - "$RESULTS_CSV" <<'PY'
import csv, statistics, sys
from collections import defaultdict

path=sys.argv[1]
rows=list(csv.DictReader(open(path)))
by=defaultdict(list)
codes=defaultdict(lambda: defaultdict(int))
for r in rows:
    ep=r['endpoint']
    t=float(r['time_total'])*1000.0
    by[ep].append(t)
    codes[ep][r['http_code']]+=1

def pct(vals,p):
    if not vals: return 0.0
    s=sorted(vals)
    k=(len(s)-1)*(p/100.0)
    f=int(k)
    c=min(f+1,len(s)-1)
    if f==c: return s[f]
    return s[f] + (s[c]-s[f])*(k-f)

print("\nEndpoint latency summary (ms)")
print("endpoint          count    mean    p50    p95    p99    max   codes")
print("-"*78)
for ep,vals in by.items():
    mean=statistics.mean(vals)
    p50=pct(vals,50)
    p95=pct(vals,95)
    p99=pct(vals,99)
    mx=max(vals)
    status=','.join(f"{k}:{v}" for k,v in sorted(codes[ep].items()))
    print(f"{ep:<16} {len(vals):>5} {mean:>7.1f} {p50:>6.1f} {p95:>6.1f} {p99:>6.1f} {mx:>6.1f}   {status}")

print(f"\nRaw CSV: {path}")
PY

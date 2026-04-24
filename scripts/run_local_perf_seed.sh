#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT_DIR}"

echo "[perf_seed] running in docker-compose redmine service"
docker compose -f test/docker-compose.yml -f test/docker-compose.base.yml exec -T redmine \
  bundle exec rails runner /usr/src/redmine/scripts/seed_perf_data.rb


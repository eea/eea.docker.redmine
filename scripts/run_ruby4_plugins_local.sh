#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONTAINER_NAME="${CONTAINER_NAME:-redmine-ruby4-plugins}"
IMAGE="${IMAGE:-redmine:ruby402-trixie-amd64}"
PLATFORM="${PLATFORM:-linux/amd64}"
PORT="${PORT:-3012}"
NETWORK="${NETWORK:-test_default}"
ADDONS_VOLUME="${ADDONS_VOLUME:-test_addons_data}"

DB_HOST="${DB_HOST:-172.21.0.4}"
DB_NAME="${DB_NAME:-redmine_test}"
DB_USER="${DB_USER:-redmine}"
DB_PASS="${DB_PASS:-password}"
DB_POOL="${DB_POOL:-5}"

SECRET_KEY_BASE="${SECRET_KEY_BASE:-ruby4-local-test-secret-key-base}"

COMPOSE_SCRIPT_HOST="${ROOT_DIR}/config/build/compose_gemfile_from_plugins.rb"
OVERRIDES_DIR_HOST="${ROOT_DIR}/config/overrides"
STARTUP_SCRIPT_HOST="/tmp/${CONTAINER_NAME}-startup.sh"

cat > "${STARTUP_SCRIPT_HOST}" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

cd /usr/src/redmine

cat > config/database.yml <<YAML
production:
  adapter: mysql2
  encoding: utf8mb4
  host: ${DB_HOST}
  username: ${DB_USER}
  password: ${DB_PASS}
  database: ${DB_NAME}
  pool: ${DB_POOL}
YAML

cp -a /addons/current/plugins/. /usr/src/redmine/plugins/ || true
cp -a /addons/current/themes/. /usr/src/redmine/public/themes/ || true

ruby /usr/local/bin/compose_gemfile_from_plugins.rb
bundle config set path '/usr/local/bundle'
bundle config set without 'development test'
bundle install --jobs 4 --retry 2

redmineup_route_files="$(find /usr/local/bundle -path '*/redmineup-*/config/routes.rb' -type f)"
if [ -n "${redmineup_route_files}" ]; then
  echo "${redmineup_route_files}" | while IFS= read -r file; do
    if grep -q "auto_completes/taggable_tags" "${file}" && ! grep -q "named_routes.key?(:auto_complete_taggable_tags)" "${file}"; then
      sed -i "/auto_completes\\/taggable_tags/ i\\  # TODO(redmineup): Remove this guard and re-test on future releases once upstream fixes duplicate named route registration. Overlap lives in redmine_contacts/config/routes.rb and redmineup/config/routes.rb for auto_completes#taggable_tags (helper: auto_complete_taggable_tags)." "${file}"
      sed -i "/auto_completes\\/taggable_tags/ i\\  unless Rails.application.routes.named_routes.key?(:auto_complete_taggable_tags)" "${file}"
      sed -i "/as: 'auto_complete_taggable_tags'/ a\\  end" "${file}"
      echo "patched ${file}"
    else
      echo "skipping patch ${file}"
    fi
  done
else
  echo "redmineup routes not found under /usr/local/bundle"
fi
bundle exec rails db:migrate RAILS_ENV=production
bundle exec rails runner -e production "puts Redmine::Plugin.all.map { |p| [p.id, p.version.to_s].join(':') }.sort.join(\"\n\")"
exec bundle exec rails server -e production -b 0.0.0.0 -p 3000
EOS

chmod +x "${STARTUP_SCRIPT_HOST}"

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

echo "Starting ${CONTAINER_NAME} from ${IMAGE} on http://localhost:${PORT}"

docker run -d \
  --name "${CONTAINER_NAME}" \
  --entrypoint bash \
  --platform "${PLATFORM}" \
  --network "${NETWORK}" \
  -p "${PORT}:3000" \
  -e "SECRET_KEY_BASE=${SECRET_KEY_BASE}" \
  -e "RAILS_ENV=production" \
  -e "DB_HOST=${DB_HOST}" \
  -e "DB_NAME=${DB_NAME}" \
  -e "DB_USER=${DB_USER}" \
  -e "DB_PASS=${DB_PASS}" \
  -e "DB_POOL=${DB_POOL}" \
  -v "${ADDONS_VOLUME}:/addons:ro" \
  -v "${COMPOSE_SCRIPT_HOST}:/usr/local/bin/compose_gemfile_from_plugins.rb:ro" \
  -v "${OVERRIDES_DIR_HOST}:/usr/src/redmine/config/overrides:ro" \
  -v "${STARTUP_SCRIPT_HOST}:/tmp/startup.sh:ro" \
  "${IMAGE}" \
  -lc '/tmp/startup.sh'

echo "Container started. Follow logs with:"
echo "  docker logs -f ${CONTAINER_NAME}"
echo "Quick check:"
echo "  curl -sS -o /dev/null -w 'code=%{http_code} ttfb=%{time_starttransfer} total=%{time_total}\n' http://localhost:${PORT}/"

#!/bin/bash

set -euo pipefail

if [ -f /usr/local/bin/common.sh ]; then
  # shellcheck disable=SC1091
  source /usr/local/bin/common.sh
fi

REDMINE_PATH=${REDMINE_PATH:-/usr/src/redmine}
REDMINE_LOCAL_PATH=${REDMINE_LOCAL_PATH:-/var/local/redmine}
MIGRATIONS_ONLY_STARTUP=${MIGRATIONS_ONLY_STARTUP:-1}
START_SERVER=${START_SERVER:-1}
START_CRON=${START_CRON:-1}
START_SOLID_QUEUE=${START_SOLID_QUEUE:-0}
CRON_IN_ASYNC_JOBS_ONLY=${CRON_IN_ASYNC_JOBS_ONLY:-1}
RAILS_MAX_THREADS=${RAILS_MAX_THREADS:-5}
WEB_CONCURRENCY=${WEB_CONCURRENCY:-1}
REQUIRE_MOUNTED_ADDONS=${REQUIRE_MOUNTED_ADDONS:-0}
MOUNTED_ADDONS_ROOT=${MOUNTED_ADDONS_ROOT:-/addons/current}
RUN_DB_MIGRATE=${RUN_DB_MIGRATE:-1}
RUN_PLUGIN_MIGRATE=${RUN_PLUGIN_MIGRATE:-auto}
WAIT_FOR_DB_TABLES=${WAIT_FOR_DB_TABLES:-}
DB_TABLE_WAIT_TIMEOUT=${DB_TABLE_WAIT_TIMEOUT:-180}
DB_TABLE_WAIT_INTERVAL=${DB_TABLE_WAIT_INTERVAL:-3}
FAST_BOOT=${FAST_BOOT:-1}
RUNTIME_PLUGIN_SYNC=${RUNTIME_PLUGIN_SYNC:-0}
RUNTIME_THEME_SYNC=${RUNTIME_THEME_SYNC:-0}
STARTUP_ASSET_FIXES=${STARTUP_ASSET_FIXES:-0}
APPLY_A1_THEME_OVERRIDES_ON_BOOT=${APPLY_A1_THEME_OVERRIDES_ON_BOOT:-0}
ASSETS_PRECOMPILE=${ASSETS_PRECOMPILE:-0}
ASSETS_PRECOMPILE_FORCE=${ASSETS_PRECOMPILE_FORCE:-0}
ASSETS_PRECOMPILE_TIMEOUT=${ASSETS_PRECOMPILE_TIMEOUT:-1200}
export RAILS_MAX_THREADS WEB_CONCURRENCY

if [ "${FAST_BOOT}" = "1" ]; then
  RUNTIME_PLUGIN_SYNC=0
  RUNTIME_THEME_SYNC=0
  STARTUP_ASSET_FIXES=0
  APPLY_A1_THEME_OVERRIDES_ON_BOOT=0
fi

if [ "${CRON_IN_ASYNC_JOBS_ONLY}" = "1" ] && [ "${START_SERVER}" = "1" ] && [ "${START_CRON}" = "1" ]; then
  echo "CRON_IN_ASYNC_JOBS_ONLY=1: disabling cron in web container, use async-jobs container for cron execution"
  START_CRON=0
fi

resolve_taskman_url() {
  local configured="${TASKMAN_URL:-${REDMINE_HOST:-}}"

  if [ -z "${configured}" ]; then
    echo "http://127.0.0.1:3000"
    return 0
  fi

  if [[ "${configured}" == http://* || "${configured}" == https://* ]]; then
    echo "${configured}"
    return 0
  fi

  echo "http://${configured}"
}

resolve_secret_key_base() {
  local token_file="${REDMINE_PATH}/config/initializers/secret_token.rb"
  local extracted=""

  if [ -n "${SECRET_KEY_BASE:-}" ]; then
    echo "${SECRET_KEY_BASE}"
    return 0
  fi

  if [ -f "${token_file}" ]; then
    extracted=$(sed -n "s/.*secret_key_base *= *'\\([^']\\+\\)'.*/\\1/p" "${token_file}" | tail -n1)
  fi

  if [ -n "${extracted}" ]; then
    echo "${extracted}"
    return 0
  fi

  ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'
}

safe_chown_tree() {
  local target="$1"

  if [ ! -e "${target}" ]; then
    return 0
  fi

  if [ -w "${target}" ]; then
    chown -R redmine:redmine "${target}" || true
    return 0
  fi

  echo "Skipping chown for ${target} (not writable, likely read-only mount)"
}

safe_chown_path() {
  local target="$1"

  if [ ! -e "${target}" ]; then
    return 0
  fi

  if [ -w "${target}" ]; then
    chown redmine:redmine "${target}" || true
    return 0
  fi

  echo "Skipping chown for ${target} (not writable, likely read-only mount)"
}

validate_mounted_addons() {
  if [ "${REQUIRE_MOUNTED_ADDONS}" != "1" ]; then
    return 0
  fi

  local missing=0

  if [ ! -d "${MOUNTED_ADDONS_ROOT}/plugins" ]; then
    echo "Missing mounted addons plugins directory: ${MOUNTED_ADDONS_ROOT}/plugins" >&2
    missing=1
  fi

  if [ ! -d "${MOUNTED_ADDONS_ROOT}/themes/${A1_THEME_ID}" ]; then
    echo "Missing mounted A1 theme directory: ${MOUNTED_ADDONS_ROOT}/themes/${A1_THEME_ID}" >&2
    missing=1
  fi

  if [ "${missing}" = "1" ]; then
    exit 1
  fi
}

link_mounted_addons() {
  if [ "${REQUIRE_MOUNTED_ADDONS}" != "1" ]; then
    return 0
  fi

  local source
  local name
  local dest

  if [ -d "${MOUNTED_ADDONS_ROOT}/plugins" ]; then
    for source in "${MOUNTED_ADDONS_ROOT}"/plugins/*; do
      [ -e "${source}" ] || continue
      name="$(basename "${source}")"
      dest="${REDMINE_PATH}/plugins/${name}"
      if [ -L "${dest}" ]; then
        rm -f "${dest}"
      fi
      if [ ! -e "${dest}" ]; then
        ln -s "${source}" "${dest}"
      fi
    done
  fi

  if [ -d "${MOUNTED_ADDONS_ROOT}/themes" ]; then
    for source in "${MOUNTED_ADDONS_ROOT}"/themes/*; do
      [ -e "${source}" ] || continue
      name="$(basename "${source}")"
      dest="${THEMES_DIR}/${name}"
      if [ -L "${dest}" ]; then
        rm -f "${dest}"
      fi
      if [ ! -e "${dest}" ]; then
        ln -s "${source}" "${dest}"
      fi
    done
  fi
}

setup_runtime_environment() {
  local taskman_url_value
  local secret_key_base_value

  taskman_url_value="$(resolve_taskman_url)"
  secret_key_base_value="$(resolve_secret_key_base)"

  export TASKMAN_URL="${taskman_url_value}"
  export SECRET_KEY_BASE="${secret_key_base_value}"

  mkdir -p "${REDMINE_PATH}"
  : > "${REDMINE_PATH}/.profile"

  append_profile_export() {
    local key="$1"
    local value="${2-}"
    printf 'export %s=%q\n' "${key}" "${value}" >> "${REDMINE_PATH}/.profile"
  }

  append_profile_export "SYNC_API_KEY" "${SYNC_API_KEY:-}"
  append_profile_export "SYNC_REDMINE_URL" "${SYNC_REDMINE_URL:-}"
  append_profile_export "GITHUB_AUTHENTICATION" "${GITHUB_AUTHENTICATION:-}"
  append_profile_export "GEM_HOME" "/usr/local/bundle"
  append_profile_export "BUNDLE_APP_CONFIG" "/usr/local/bundle"
  append_profile_export "PATH" "/usr/local/bundle/bin:${PATH}"
  append_profile_export "SECRET_KEY_BASE" "${secret_key_base_value}"
  append_profile_export "RAILS_ENV" "${RAILS_ENV:-production}"
  chown redmine:redmine "${REDMINE_PATH}/.profile" || true
  chmod 600 "${REDMINE_PATH}/.profile" || true

  echo "TZ=${TZ:-UTC}" >> /etc/default/cron

  cat > /etc/environment <<EOF
export TZ=${TZ:-UTC}

# Incoming emails API: Administration -> Settings -> Incoming email - API key
HELPDESK_EMAIL_KEY=${HELPDESK_EMAIL_KEY:-}
# Host for the helpdesk api from where to fetch support mails
TASKMAN_URL=${taskman_url_value}
SECRET_KEY_BASE=${secret_key_base_value}

T_EMAIL_HOST=${T_EMAIL_HOST:-}
T_EMAIL_PORT=${T_EMAIL_PORT:-}
T_EMAIL_USER=${T_EMAIL_USER:-}
T_EMAIL_PASS=${T_EMAIL_PASS:-}
T_EMAIL_FOLDER=Inbox
T_EMAIL_SSL=true

# EEA Entra ID application credentials
ENTRA_ID_TENANT_ID=${ENTRA_ID_TENANT_ID:-}
ENTRA_ID_CLIENT_ID=${ENTRA_ID_CLIENT_ID:-}
ENTRA_ID_CLIENT_SECRET=${ENTRA_ID_CLIENT_SECRET:-}
EOF
}

ensure_database_yml() {
  local db_file="${REDMINE_PATH}/config/database.yml"
  local rails_env="${RAILS_ENV:-production}"
  local db_host="${REDMINE_DB_MYSQL:-mysql}"
  local db_port="${REDMINE_DB_PORT:-3306}"
  local db_name="${REDMINE_DB_DATABASE:-redmine}"
  local db_user="${REDMINE_DB_USERNAME:-redmine}"
  local db_pass="${REDMINE_DB_PASSWORD:-}"
  local db_pool="${REDMINE_DB_POOL:-${RAILS_MAX_THREADS:-5}}"
  local test_db_host="${REDMINE_TEST_DB_MYSQL:-${db_host}}"
  local test_db_port="${REDMINE_TEST_DB_PORT:-${db_port}}"
  local test_db_name="${REDMINE_TEST_DB_DATABASE:-${db_name}}"
  local test_db_user="${REDMINE_TEST_DB_USERNAME:-${db_user}}"
  local test_db_pass="${REDMINE_TEST_DB_PASSWORD:-${db_pass}}"
  local test_db_pool="${REDMINE_TEST_DB_POOL:-${db_pool}}"

  append_db_block() {
    local env_name="$1"
    local host="$2"
    local port="$3"
    local name="$4"
    local user="$5"
    local pass="$6"
    local pool="$7"

    cat >> "${db_file}" <<EOF
${env_name}:
  adapter: mysql2
  host: "${host}"
  port: "${port}"
  database: "${name}"
  username: "${user}"
  password: "${pass}"
  pool: ${pool}
  encoding: utf8mb4
EOF
  }

  mkdir -p "$(dirname "${db_file}")"

  if [ ! -f "${db_file}" ]; then
    append_db_block "${rails_env}" "${db_host}" "${db_port}" "${db_name}" "${db_user}" "${db_pass}" "${db_pool}"
  fi

  if ! grep -qE '^test:' "${db_file}"; then
    [ -s "${db_file}" ] && printf "\n" >> "${db_file}"
    append_db_block "test" "${test_db_host}" "${test_db_port}" "${test_db_name}" "${test_db_user}" "${test_db_pass}" "${test_db_pool}"
  fi
}

prepare_addons_assets_in_place() {
  local resolved_themes_dir="${REDMINE_PATH}/public/themes"
  local resolved_theme_id="${A1_THEME_ID:-a1}"

  if [ -d "${REDMINE_PATH}/themes" ]; then
    resolved_themes_dir="${REDMINE_PATH}/themes"
  fi

  if [ -x /usr/local/bin/prepare_addons_assets.sh ]; then
    ADDONS_CURRENT_DIR="${REDMINE_PATH}" \
    PLUGINS_DIR="${REDMINE_PATH}/plugins" \
    THEMES_DIR="${resolved_themes_dir}" \
    PUBLIC_DIR="${REDMINE_PATH}/public" \
    A1_THEME_ID="${resolved_theme_id}" \
    /usr/local/bin/prepare_addons_assets.sh
  fi
}

prepare_asset_warning_fixes() {
  local jquery_ui_css="${REDMINE_PATH}/app/assets/stylesheets/jquery/jquery-ui-1.13.2.css"
  local ai_helper_config_dir="${REDMINE_PATH}/config/ai_helper"
  local ai_helper_config_file="${ai_helper_config_dir}/config.json"

  # Drop broken ThemeRoller metadata URL encodings that Sprockets tries to resolve.
  if [ -f "${jquery_ui_css}" ] && grep -q '%22images%2Fui-icons_' "${jquery_ui_css}"; then
    sed -i '/%22images%2Fui-icons_/d' "${jquery_ui_css}"
  fi

  prepare_addons_assets_in_place

  # Silence ai helper warning when external MCP config is intentionally unset.
  if [ ! -f "${ai_helper_config_file}" ]; then
    mkdir -p "${ai_helper_config_dir}"
    printf "{}\n" > "${ai_helper_config_file}"
  fi
}

apply_a1_theme_backport_overrides() {
  if [ -x /usr/local/bin/apply_a1_theme_overrides.sh ] && [ -w "${THEMES_DIR}/${A1_THEME_ID}" ]; then
    THEMES_DIR="${THEMES_DIR}" A1_THEME_ID="${A1_THEME_ID}" /usr/local/bin/apply_a1_theme_overrides.sh || true
  elif [ -d "${THEMES_DIR}/${A1_THEME_ID}" ]; then
    echo "Skipping runtime A1 override application for ${THEMES_DIR}/${A1_THEME_ID} (not writable)"
  fi
}

start_cron_background() {
  if [ "${START_CRON}" = "1" ]; then
    touch /etc/crontab /etc/cron.*/*
    if [ -n "${RESTART_CRON:-}" ] && [ "$(grep -c 'rails server' /var/redmine_jobs.txt)" -eq 0 ] ; then
      echo "${RESTART_CRON} kill -2 \$(ps -fu redmine | grep 'rails server' | grep -v grep | awk '{print \$2}')" >> /var/redmine_jobs.txt
    fi
    crontab /var/redmine_jobs.txt
    chmod 600 /etc/crontab

    systemctl restart rsyslog
    service cron restart
  else
    echo "Skipping cron startup because START_CRON=${START_CRON}"
  fi
}

run_jobs_only_foreground() {
  if [ "${START_CRON}" = "1" ] && [ "${START_SOLID_QUEUE}" = "1" ]; then
    start_cron_background
    echo "Starting Solid Queue supervisor in foreground with cron in background"
    cd "${REDMINE_PATH}"
    exec bundle exec rake solid_queue:start
  fi

  if [ "${START_SOLID_QUEUE}" = "1" ]; then
    echo "Starting Solid Queue supervisor in foreground"
    cd "${REDMINE_PATH}"
    exec bundle exec rake solid_queue:start
  fi

  if [ "${START_CRON}" = "1" ]; then
    touch /etc/crontab /etc/cron.*/*
    crontab /var/redmine_jobs.txt
    chmod 600 /etc/crontab
    echo "TZ=$TZ" >> /etc/default/cron
    echo "Starting cron in foreground (jobs-only mode)"
    exec cron -f
  fi

  echo "START_SERVER=0 requires START_CRON=1 or START_SOLID_QUEUE=1"
  exit 1
}

run_migration_phase() {
  local phase="$1"
  ruby "${REDMINE_PATH}/config/runtime/migration_runner.rb" "${phase}"
}

should_run_plugin_migrate() {
  # Backward compatibility: explicit REDMINE_PLUGINS_MIGRATE wins.
  case "${REDMINE_PLUGINS_MIGRATE:-}" in
    yes|true|1) return 0 ;;
    no|false|0) return 1 ;;
  esac

  case "${RUN_PLUGIN_MIGRATE}" in
    yes|true|1) return 0 ;;
    no|false|0) return 1 ;;
  esac

  # auto mode: when DB migration is enabled (migration job), migrate plugins too.
  [ "${RUN_DB_MIGRATE}" = "1" ]
}

assets_manifest_exists() {
  local assets_dir="${REDMINE_PATH}/public/assets"
  compgen -G "${assets_dir}/.sprockets-manifest-*.json" >/dev/null 2>&1
}

run_assets_precompile_if_enabled() {
  if [ "${ASSETS_PRECOMPILE}" != "1" ]; then
    echo "Skipping assets:precompile because ASSETS_PRECOMPILE=${ASSETS_PRECOMPILE}"
    return 0
  fi

  if [ "${ASSETS_PRECOMPILE_FORCE}" != "1" ] && assets_manifest_exists; then
    echo "Skipping assets:precompile because sprockets manifest already exists"
    return 0
  fi

  echo "Running assets:precompile (ASSETS_PRECOMPILE_FORCE=${ASSETS_PRECOMPILE_FORCE})"
  if ! timeout "${ASSETS_PRECOMPILE_TIMEOUT}" bundle exec rake assets:precompile; then
    echo "assets:precompile failed or timed out after ${ASSETS_PRECOMPILE_TIMEOUT}s"
    return 1
  fi

  return 0
}

ensure_bundle_ready() {
  bundle config set path '/usr/local/bundle' >/dev/null 2>&1 || true
  bundle config set --local without 'development test' >/dev/null 2>&1 || true

  if bundle check >/dev/null 2>&1; then
    return 0
  fi

  if [ "${FAST_BOOT}" != "1" ]; then
    echo "Bundle check failed, attempting online runtime bundle install"
    bundle install --jobs 4 --no-cache
    bundle clean --force
    return 0
  fi

  echo "Missing gems in runtime bundle and runtime installation is disabled (FAST_BOOT=${FAST_BOOT})."
  echo "Set FAST_BOOT=0 to allow runtime bundle install, or rebuild image with complete bundle."
  return 1
}

wait_for_db_tables() {
  if [ -z "${WAIT_FOR_DB_TABLES}" ]; then
    return 0
  fi

  WAIT_FOR_DB_TABLES="${WAIT_FOR_DB_TABLES}" \
  DB_TABLE_WAIT_TIMEOUT="${DB_TABLE_WAIT_TIMEOUT}" \
  DB_TABLE_WAIT_INTERVAL="${DB_TABLE_WAIT_INTERVAL}" \
  REDMINE_DB_MYSQL="${REDMINE_DB_MYSQL:-mysql}" \
  REDMINE_DB_DATABASE="${REDMINE_DB_DATABASE:-redmine}" \
  REDMINE_DB_USERNAME="${REDMINE_DB_USERNAME:-redmine}" \
  REDMINE_DB_PASSWORD="${REDMINE_DB_PASSWORD:-}" \
  ruby <<'RUBY'
require "mysql2"

tables = ENV.fetch("WAIT_FOR_DB_TABLES").split(",").map(&:strip).reject(&:empty?)
timeout = ENV.fetch("DB_TABLE_WAIT_TIMEOUT", "180").to_i
interval = ENV.fetch("DB_TABLE_WAIT_INTERVAL", "3").to_i
deadline = Time.now + timeout

connection_args = {
  host: ENV.fetch("REDMINE_DB_MYSQL"),
  username: ENV.fetch("REDMINE_DB_USERNAME"),
  password: ENV.fetch("REDMINE_DB_PASSWORD", ""),
  database: ENV.fetch("REDMINE_DB_DATABASE"),
  reconnect: true,
  connect_timeout: 5
}

loop do
  begin
    client = Mysql2::Client.new(**connection_args)
    found = client.query("SHOW TABLES").map { |row| row.values.first }
    missing = tables - found
    exit 0 if missing.empty?
    warn "Waiting for database tables: #{missing.join(', ')}"
  rescue StandardError => e
    warn "Waiting for database tables failed: #{e.class}: #{e.message}"
  ensure
    client&.close
  end

  exit 1 if Time.now >= deadline
  sleep interval
end
RUBY
}

if [ "${MIGRATIONS_ONLY_STARTUP}" = "1" ]; then
  # Keep startup minimal for k8s: initialize app env via upstream entrypoint,
  # run migrations/bootstrap once, then boot the server directly.
  set -euo pipefail
  if [ "${STARTUP_ASSET_FIXES}" = "1" ]; then
    prepare_asset_warning_fixes
  else
    echo "Skipping startup asset warning fixes (STARTUP_ASSET_FIXES=${STARTUP_ASSET_FIXES})"
  fi
  setup_runtime_environment
  ensure_database_yml
  export ADMIN_BOOTSTRAP_PASSWORD=${ADMIN_BOOTSTRAP_PASSWORD:-Admin123!}
  export DEFAULT_THEME=${DEFAULT_THEME:-a1}
  export REDMINE_PLUGINS_MIGRATE=${REDMINE_PLUGINS_MIGRATE:-}
  BOOTSTRAP_RAILS_LOG_LEVEL=${BOOTSTRAP_RAILS_LOG_LEVEL:-error}
  ADMIN_BOOTSTRAP_ENABLE=${ADMIN_BOOTSTRAP_ENABLE:-0}
  ADMIN_BOOTSTRAP_TIMEOUT=${ADMIN_BOOTSTRAP_TIMEOUT:-90}
  THEMES_DIR="${REDMINE_PATH}/public/themes"
  if [ -d "${REDMINE_PATH}/themes" ]; then
    THEMES_DIR="${REDMINE_PATH}/themes"
  fi
  A1_THEME_ID=${A1_THEME_ID:-a1}
  validate_mounted_addons
  link_mounted_addons
  prepare_addons_assets_in_place
  if [ "${APPLY_A1_THEME_OVERRIDES_ON_BOOT}" = "1" ]; then
    apply_a1_theme_backport_overrides
  else
    echo "Skipping A1 runtime override patching (APPLY_A1_THEME_OVERRIDES_ON_BOOT=${APPLY_A1_THEME_OVERRIDES_ON_BOOT})"
  fi

  if [ "${RUN_DB_MIGRATE}" = "1" ]; then
    run_migration_phase db
  else
    echo "Skipping db:migrate because RUN_DB_MIGRATE=${RUN_DB_MIGRATE}"
  fi
  run_assets_precompile_if_enabled
  if should_run_plugin_migrate; then
    run_migration_phase plugins
  else
    echo "Skipping redmine:plugins:migrate (RUN_PLUGIN_MIGRATE=${RUN_PLUGIN_MIGRATE}, REDMINE_PLUGINS_MIGRATE=${REDMINE_PLUGINS_MIGRATE:-unset})"
  fi

  if [ "${ADMIN_BOOTSTRAP_ENABLE}" = "1" ]; then
    if ! timeout "${ADMIN_BOOTSTRAP_TIMEOUT}" bundle exec rails runner "
      password = ENV.fetch('ADMIN_BOOTSTRAP_PASSWORD', 'Admin123!')
      theme = ENV.fetch('DEFAULT_THEME', 'a1')
      admin = User.find_by(login: 'admin')
      if admin
        admin.auth_source_id = nil if admin.respond_to?(:auth_source_id=)
        admin.password = password
        admin.password_confirmation = password
        admin.must_change_passwd = false if admin.respond_to?(:must_change_passwd=)
        admin.twofa_required = false if admin.respond_to?(:twofa_required=)
        admin.twofa_scheme = nil if admin.respond_to?(:twofa_scheme=)
        admin.twofa_totp_key = nil if admin.respond_to?(:twofa_totp_key=)
        admin.twofa_totp_last_used_at = nil if admin.respond_to?(:twofa_totp_last_used_at=)
        admin.save!
        Token.where(user_id: admin.id).where('action LIKE ?', 'twofa%').delete_all
      end
      Setting['ui_theme'] = theme
    "; then
      echo "Admin/theme bootstrap failed or timed out; continuing startup"
    fi
  fi
  rm -f ${REDMINE_PATH}/tmp/pids/server.pid

  if [ "${START_SERVER}" != "1" ] && [ "${START_CRON}" != "1" ] && [ "${START_SOLID_QUEUE}" != "1" ]; then
    echo "Migration-only startup completed"
    exit 0
  fi

  if [ "${START_SERVER}" = "1" ]; then
    ensure_bundle_ready
    start_cron_background
    export REDMINE_NO_DB_MIGRATE=1
    export REDMINE_PLUGINS_MIGRATE=
    exec bundle exec rails server -b 0.0.0.0
  fi

  wait_for_db_tables
  run_jobs_only_foreground
fi

if [ "${STARTUP_ASSET_FIXES}" = "1" ]; then
  prepare_asset_warning_fixes
else
  echo "Skipping startup asset warning fixes (STARTUP_ASSET_FIXES=${STARTUP_ASSET_FIXES})"
fi

PLUGIN_CACHE_DIR=/install_plugins
PLUGIN_FALLBACK_DIR=/tmp/install_plugins
THEME_CACHE_DIR=/install_themes
THEME_FALLBACK_DIR=/tmp/install_themes
RUNTIME_ADDONS_CHANGED=0

mkdir -p "${PLUGIN_FALLBACK_DIR}"
mkdir -p "${THEME_FALLBACK_DIR}"

is_valid_zip() {
  unzip -tqq "$1" >/dev/null 2>&1
}

download_archive() {
  local url="$1"
  local destination="$2"
  local user="${3:-}"
  local password="${4:-}"
  local label="$5"
  local tmp_file="${destination}.partial"

  rm -f "${tmp_file}"

  if command -v wget >/dev/null 2>&1; then
    if [ -n "${user}" ]; then
      wget -q --user="${user}" --password="${password}" -O "${tmp_file}" "${url}"
    else
      wget -q -O "${tmp_file}" "${url}"
    fi
  elif command -v curl >/dev/null 2>&1; then
    if [ -n "${user}" ]; then
      curl -fsSL -u "${user}:${password}" -o "${tmp_file}" "${url}"
    else
      curl -fsSL -o "${tmp_file}" "${url}"
    fi
  else
    echo "Neither wget nor curl is available for ${label} download"
    exit 1
  fi

  mv "${tmp_file}" "${destination}"

  if ! is_valid_zip "${destination}"; then
    rm -f "${destination}"
    echo "Downloaded ${label} is not a valid zip archive: ${url}"
    exit 1
  fi
}

resolve_archive() {
  local preferred_archive="$1"
  local fallback_archive="$2"
  local remote_url="$3"
  local user="${4:-}"
  local password="${5:-}"
  local label="$6"

  if [ -f "${preferred_archive}" ]; then
    if is_valid_zip "${preferred_archive}"; then
      echo "${preferred_archive}"
      return 0
    fi
    echo "Removing invalid cached ${label}: ${preferred_archive}"
    rm -f "${preferred_archive}"
  fi

  if [ -f "${fallback_archive}" ]; then
    if is_valid_zip "${fallback_archive}"; then
      echo "${fallback_archive}"
      return 0
    fi
    echo "Removing invalid cached ${label}: ${fallback_archive}"
    rm -f "${fallback_archive}"
  fi

  echo "Found missing ${label}, will download and install it" >&2
  download_archive "${remote_url}" "${fallback_archive}" "${user}" "${password}" "${label}"
  echo "${fallback_archive}"
}

setup_runtime_environment
ensure_database_yml
ensure_bundle_ready
start_cron_background

REDMINE_SMTP_HOST=${REDMINE_SMTP_HOST:-postfix}
REDMINE_SMTP_PORT=${REDMINE_SMTP_PORT:-25}
REDMINE_SMTP_DOMAIN=${REDMINE_SMTP_DOMAIN:-eionet.europa.eu}
REDMINE_SMTP_STARTTLSAUTO=${REDMINE_SMTP_STARTTLSAUTO:-true}

first_line=$(awk '/smtp_settings/ {print FNR}' ${REDMINE_PATH}/config/configuration.yml)
head -n ${first_line} ${REDMINE_PATH}/config/configuration.yml > /tmp/configuration.yml
if [[ "${REDMINE_SMTP_TLS}" == "false" ]]; then
  echo "      enable_starttls_auto: ${REDMINE_SMTP_STARTTLSAUTO}
      address: \"${REDMINE_SMTP_HOST}\"
      port: ${REDMINE_SMTP_PORT}
      domain: \"${REDMINE_SMTP_DOMAIN}\"
      tls: false" >> /tmp/configuration.yml
else
  echo "      enable_starttls_auto: ${REDMINE_SMTP_STARTTLSAUTO}
      address: \"${REDMINE_SMTP_HOST}\"
      port: ${REDMINE_SMTP_PORT}
      domain: \"${REDMINE_SMTP_DOMAIN}\"
" >> /tmp/configuration.yml
fi

last_line=$(sed -n '/smtp_settings/,/^$/p' ${REDMINE_PATH}/config/configuration.yml | wc -l )
let last_part=${first_line}+${last_line}-1
tail --lines=+$last_part ${REDMINE_PATH}/config/configuration.yml >> /tmp/configuration.yml
diff /tmp/configuration.yml ${REDMINE_PATH}/config/configuration.yml || true
mv /tmp/configuration.yml ${REDMINE_PATH}/config/configuration.yml


# delete empty plugin artifacts only when the cache mount is writable
if [ -d "${PLUGIN_CACHE_DIR}" ] && [ -w "${PLUGIN_CACHE_DIR}" ]; then
  find "${PLUGIN_CACHE_DIR}" -size 0 -type f -exec rm {} \;
fi

MANIFEST_SCRIPT="${REDMINE_PATH}/config/lib/addons_manifest.rb"
if [ ! -f "${MANIFEST_SCRIPT}" ]; then
  echo "addons manifest helper not found at ${MANIFEST_SCRIPT}" >&2
  exit 1
fi
if [ ! -f "${REDMINE_PATH}/addons.cfg" ]; then
  echo "addons.cfg not found at ${REDMINE_PATH}/addons.cfg" >&2
  exit 1
fi

manifest_cmd=(ruby "${MANIFEST_SCRIPT}")

ADDONS_BASE_URL="${ADDONS_BASE_URL:-${PLUGINS_URL%/plugins}}"

while IFS=: read -r plugin_kind plugin_name plugin_location plugin_file; do
  [ "${plugin_kind}" = "plugin" ] || continue
  plugin_archive=""

  if [ ! -d "${REDMINE_PATH}/plugins/${plugin_name}" ]; then
    # Always prefer already-mounted local caches (e.g. /install_plugins) so boot
    # works without remote credentials. Only download when runtime sync is enabled.
    if [ -f "${PLUGIN_CACHE_DIR}/${plugin_file}" ]; then
      plugin_archive="${PLUGIN_CACHE_DIR}/${plugin_file}"
    elif [ -f "${PLUGIN_FALLBACK_DIR}/${plugin_file}" ]; then
      plugin_archive="${PLUGIN_FALLBACK_DIR}/${plugin_file}"
    elif [ "${RUNTIME_PLUGIN_SYNC}" = "1" ] && [ -n "${ADDONS_BASE_URL:-}" ]; then
      plugin_archive=$(resolve_archive "${PLUGIN_CACHE_DIR}/${plugin_file}" "${PLUGIN_FALLBACK_DIR}/${plugin_file}" "${ADDONS_BASE_URL}/${plugin_location}/${plugin_file}" "${PLUGINS_USER:-}" "${PLUGINS_PASSWORD:-}" "plugin - ${plugin_file}")
    fi

    if [ -n "${plugin_archive}" ]; then
      echo "Found missing plugin - ${plugin_name}, will install it"
      unzip -d "${REDMINE_PATH}/plugins" -o "${plugin_archive}"
      REDMINE_PLUGINS_MIGRATE="yes"
      RUNTIME_ADDONS_CHANGED=1
    elif [ "${RUNTIME_PLUGIN_SYNC}" = "1" ] && [ -n "${ADDONS_BASE_URL:-}" ]; then
      echo "Missing plugin archive for ${plugin_name} (${plugin_file}) even after sync attempt"
      exit 1
    else
      echo "Missing plugin ${plugin_name} (${plugin_file}) and runtime sync is disabled; keeping current startup mode."
    fi
  fi
done < <("${manifest_cmd[@]}" list)

if [ "${RUNTIME_PLUGIN_SYNC}" = "1" ] && [ -n "${ADDONS_BASE_URL:-}" ]; then

  #remove old plugins only from writable caches
  if [ -d "${PLUGIN_CACHE_DIR}" ] && [ -w "${PLUGIN_CACHE_DIR}" ]; then
    for file in  ${PLUGIN_CACHE_DIR}/*; do 
      [ -e "$file" ] || continue
      if [ "$("${manifest_cmd[@]}" has-plugin-archive "${file##*/}")" != "1" ]; then
           rm "$file"
      fi  
    done 
  fi

  if [[ "${REDMINE_PLUGINS_MIGRATE:-no}" == "yes" ]]; then
         touch ${REDMINE_PATH}/log/redmine_helpdesk.log
         chown redmine:redmine ${REDMINE_PATH}/log/redmine_helpdesk.log
         export REDMINE_PLUGINS_MIGRATE
  fi

fi

# Compatibility shim for Redmine Contacts Helpdesk:
# some packaged versions still require avatars_helper_patch.rb but do not ship it.
HELPDESK_PATCH_DIR="${REDMINE_PATH}/plugins/redmine_contacts_helpdesk/lib/redmine_helpdesk/patches"
HELPDESK_PATCH_FILE="${HELPDESK_PATCH_DIR}/avatars_helper_patch.rb"
if [ -d "${REDMINE_PATH}/plugins/redmine_contacts_helpdesk/lib/redmine_helpdesk" ]; then
  mkdir -p "${HELPDESK_PATCH_DIR}"
  if [ ! -f "${HELPDESK_PATCH_FILE}" ]; then
    cat > "${HELPDESK_PATCH_FILE}" <<'RUBY'
module RedmineHelpdesk
  module Patches
    module AvatarsHelperPatch
      def self.included(base); end
    end
  end
end
RUBY
    RUNTIME_ADDONS_CHANGED=1
  fi
fi

THEMES_DIR="${REDMINE_PATH}/public/themes"
if [ -d "${REDMINE_PATH}/themes" ]; then
  THEMES_DIR="${REDMINE_PATH}/themes"
fi

A1_THEME_ID=${A1_THEME_ID:-a1}
A1_THEME_ZIP=${A1_THEME_ZIP:-}
A1_THEME_URL=${A1_THEME_URL:-}
A1_THEME_USER=${A1_THEME_USER:-${PLUGINS_USER:-}}
A1_THEME_PASSWORD=${A1_THEME_PASSWORD:-${PLUGINS_PASSWORD:-}}

if [ -z "${A1_THEME_ZIP}" ]; then
  A1_THEME_ZIP="$("${manifest_cmd[@]}" theme-archive)"
fi
if [ -z "${A1_THEME_ZIP}" ]; then
  A1_THEME_ZIP="a1_theme-4_1_2.zip"
fi
THEME_LOCATION="$("${manifest_cmd[@]}" theme-location)"
[ -n "${THEME_LOCATION}" ] || THEME_LOCATION="themes"

if [ -z "${A1_THEME_URL}" ] && [ -n "${ADDONS_BASE_URL:-}" ]; then
  A1_THEME_URL="${ADDONS_BASE_URL}/${THEME_LOCATION}/${A1_THEME_ZIP}"
fi

validate_mounted_addons
link_mounted_addons

if [ "${RUNTIME_THEME_SYNC}" = "1" ] && [ -n "${A1_THEME_URL}" ] && [ ! -d "${THEMES_DIR}/${A1_THEME_ID}" ]; then
  theme_archive=$(resolve_archive "${THEME_CACHE_DIR}/${A1_THEME_ZIP}" "${THEME_FALLBACK_DIR}/${A1_THEME_ZIP}" "${A1_THEME_URL}" "${A1_THEME_USER}" "${A1_THEME_PASSWORD}" "theme - ${A1_THEME_ZIP}")

  if [ -n "${A1_THEME_SHA256:-}" ]; then
    echo "${A1_THEME_SHA256}  ${theme_archive}" | sha256sum -c -
  fi

  unzip -d "${THEMES_DIR}" -o "${theme_archive}"
  RUNTIME_ADDONS_CHANGED=1
fi

apply_a1_theme_backport_overrides

if [ "${RUNTIME_ADDONS_CHANGED}" = "1" ] || ! bundle check >/dev/null 2>&1; then
  bundle config set path '/usr/local/bundle' >/dev/null 2>&1 || true
  bundle config set --local without 'development test' >/dev/null 2>&1 || true

  if [ "${FAST_BOOT}" != "1" ]; then
    echo "Installing runtime plugin/theme gem dependencies"
    bundle install --jobs 4 --no-cache
    bundle clean --force
  else
    echo "Runtime gem installation is disabled (FAST_BOOT=${FAST_BOOT})."
    echo "Build a complete image with all gems/plugins/themes baked in, or set FAST_BOOT=0 for runtime bundle install."
    exit 1
  fi
fi

#ensure correct permissions
safe_chown_tree /usr/src/redmine/plugins
safe_chown_tree "${THEMES_DIR}"
safe_chown_path /usr/src/redmine/tmp

if [ "${START_SERVER}" = "1" ]; then
  exec bundle exec rails server -b 0.0.0.0
else
  wait_for_db_tables
  run_jobs_only_foreground
fi

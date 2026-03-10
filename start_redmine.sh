#!/bin/bash

REDMINE_PATH=${REDMINE_PATH:-/usr/src/redmine}
REDMINE_LOCAL_PATH=${REDMINE_LOCAL_PATH:-/var/local/redmine}
MIGRATIONS_ONLY_STARTUP=${MIGRATIONS_ONLY_STARTUP:-1}

prepare_asset_warning_fixes() {
  local jquery_ui_css="${REDMINE_PATH}/app/assets/stylesheets/jquery/jquery-ui-1.13.2.css"
  local app_images_dir="${REDMINE_PATH}/app/assets/images"
  local ai_helper_config_dir="${REDMINE_PATH}/config/ai_helper"
  local ai_helper_config_file="${ai_helper_config_dir}/config.json"

  ensure_asset_file() {
    local destination="$1"
    shift
    local source

    mkdir -p "$(dirname "${destination}")"
    if [ -f "${destination}" ]; then
      return 0
    fi

    for source in "$@"; do
      if [ -f "${source}" ]; then
        cp "${source}" "${destination}"
        return 0
      fi
    done

    : > "${destination}"
  }

  # Drop broken ThemeRoller metadata URL encodings that Sprockets tries to resolve.
  if [ -f "${jquery_ui_css}" ] && grep -q '%22images%2Fui-icons_' "${jquery_ui_css}"; then
    sed -i '/%22images%2Fui-icons_/d' "${jquery_ui_css}"
  fi

  # Normalize plugin css paths that use unresolved relative URLs.
  for css in \
    "${REDMINE_PATH}/plugins/redmine_contacts/assets/stylesheets/money.css" \
    "${REDMINE_PATH}/plugins/redmineup/assets/stylesheets/money.css"; do
    if [ -f "${css}" ]; then
      sed -i \
        -e 's#\.\./images/money\.png#money.png#g' \
        -e 's#\.\./images/bullet_go\.png#bullet_go.png#g' \
        -e 's#\.\./images/bullet_end\.png#bullet_end.png#g' \
        -e 's#\.\./images/bullet_diamond\.png#bullet_diamond.png#g' \
        "${css}"
    fi
  done

  for css in \
    "${REDMINE_PATH}/plugins/redmine_contacts/assets/stylesheets/select2.css" \
    "${REDMINE_PATH}/plugins/redmine_contacts/assets/stylesheets/calendars.css" \
    "${REDMINE_PATH}/plugins/redmine_contacts_helpdesk/assets/stylesheets/helpdesk.css"; do
    if [ -f "${css}" ]; then
      sed -i \
        -e 's#\.\./images/vcard\.png#vcard.png#g' \
        -e 's#\.\./\.\./\.\./images/bullet_go\.png#bullet_go.png#g' \
        -e 's#\.\./\.\./\.\./images/bullet_end\.png#bullet_end.png#g' \
        -e 's#\.\./\.\./\.\./images/bullet_diamond\.png#bullet_diamond.png#g' \
        -e 's#\.\./\.\./\.\./loading\.gif#loading.gif#g' \
        "${css}"
    fi
  done

  for theme_css in \
    "${REDMINE_PATH}/themes/a1/stylesheets/application.css" \
    "${REDMINE_PATH}/public/themes/a1/stylesheets/application.css"; do
    if [ -f "${theme_css}" ]; then
      sed -i 's#/stylesheets/jquery/images/#jquery/#g' "${theme_css}"
    fi
  done

  # Provide canonical assets for css references used by bundled plugins/themes.
  mkdir -p "${app_images_dir}"
  ensure_asset_file "${app_images_dir}/img/resizer.png" \
    "${REDMINE_PATH}/app/assets/images/resizer.png"
  ensure_asset_file "${app_images_dir}/money.png" \
    "${REDMINE_PATH}/plugins/redmine_contacts/assets/images/money.png" \
    "${REDMINE_PATH}/plugins/redmineup/assets/images/money.png"
  ensure_asset_file "${app_images_dir}/bullet_go.png" \
    "${REDMINE_PATH}/plugins/redmine_contacts/assets/images/bullet_go.png" \
    "${REDMINE_PATH}/plugins/redmineup/assets/images/bullet_go.png"
  ensure_asset_file "${app_images_dir}/bullet_end.png" \
    "${REDMINE_PATH}/plugins/redmine_contacts/assets/images/bullet_end.png" \
    "${REDMINE_PATH}/plugins/redmineup/assets/images/bullet_end.png"
  ensure_asset_file "${app_images_dir}/bullet_diamond.png" \
    "${REDMINE_PATH}/plugins/redmine_contacts/assets/images/bullet_diamond.png" \
    "${REDMINE_PATH}/plugins/redmineup/assets/images/bullet_diamond.png"
  ensure_asset_file "${app_images_dir}/vcard.png" \
    "${REDMINE_PATH}/plugins/redmine_contacts/assets/images/vcard.png" \
    "${REDMINE_PATH}/plugins/redmineup/assets/images/vcard.png"
  ensure_asset_file "${app_images_dir}/loading.gif" \
    "${REDMINE_PATH}/plugins/redmine_contacts_helpdesk/assets/images/loading.gif"

  # Silence ai helper warning when external MCP config is intentionally unset.
  if [ ! -f "${ai_helper_config_file}" ]; then
    mkdir -p "${ai_helper_config_dir}"
    printf "{}\n" > "${ai_helper_config_file}"
  fi
}

if [ "${MIGRATIONS_ONLY_STARTUP}" = "1" ]; then
  # Keep startup minimal for k8s: initialize app env via upstream entrypoint,
  # run migrations/bootstrap once, then boot the server directly.
  set -euo pipefail
  prepare_asset_warning_fixes
  export ADMIN_BOOTSTRAP_PASSWORD=${ADMIN_BOOTSTRAP_PASSWORD:-Admin123!}
  export DEFAULT_THEME=${DEFAULT_THEME:-a1}
  export REDMINE_PLUGINS_MIGRATE=${REDMINE_PLUGINS_MIGRATE:-yes}
  BOOTSTRAP_RAILS_LOG_LEVEL=${BOOTSTRAP_RAILS_LOG_LEVEL:-error}
  BOOTSTRAP_RETRIES=${BOOTSTRAP_RETRIES:-30}
  BOOTSTRAP_RETRY_DELAY=${BOOTSTRAP_RETRY_DELAY:-2}
  bootstrap_ok=0
  for attempt in $(seq 1 "${BOOTSTRAP_RETRIES}"); do
    if RAILS_LOG_LEVEL="${BOOTSTRAP_RAILS_LOG_LEVEL}" /docker-entrypoint.sh rails runner "
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
      bootstrap_ok=1
      break
    fi
    echo "Bootstrap attempt ${attempt}/${BOOTSTRAP_RETRIES} failed; retrying in ${BOOTSTRAP_RETRY_DELAY}s..."
    sleep "${BOOTSTRAP_RETRY_DELAY}"
  done
  if [ "${bootstrap_ok}" != "1" ]; then
    echo "Bootstrap failed after ${BOOTSTRAP_RETRIES} attempts"
    exit 1
  fi
  rm -f ${REDMINE_PATH}/tmp/pids/server.pid
  exec gosu redmine bundle exec rails server -b 0.0.0.0
fi

prepare_asset_warning_fixes

PLUGIN_CACHE_DIR=/install_plugins
PLUGIN_FALLBACK_DIR=/tmp/install_plugins
THEME_CACHE_DIR=/install_themes
THEME_FALLBACK_DIR=/tmp/install_themes
RUNTIME_ADDONS_CHANGED=0
FAST_BOOT=${FAST_BOOT:-1}
RUNTIME_PLUGIN_SYNC=${RUNTIME_PLUGIN_SYNC:-0}
RUNTIME_THEME_SYNC=${RUNTIME_THEME_SYNC:-0}
RUNTIME_BUNDLE_INSTALL=${RUNTIME_BUNDLE_INSTALL:-0}

if [ "${FAST_BOOT}" = "1" ]; then
  RUNTIME_PLUGIN_SYNC=0
  RUNTIME_THEME_SYNC=0
fi

mkdir -p "${PLUGIN_FALLBACK_DIR}"
mkdir -p "${THEME_FALLBACK_DIR}"
touch "${REDMINE_PATH}/.profile"

append_profile_export() {
  local key="$1"
  local value="${2-}"
  printf 'export %s=%q\n' "${key}" "${value}" >> "${REDMINE_PATH}/.profile"
}

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

if [ "${START_CRON:-1}" = "1" ]; then
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

append_profile_export "SYNC_API_KEY" "${SYNC_API_KEY:-}"
append_profile_export "SYNC_REDMINE_URL" "${SYNC_REDMINE_URL:-}"
append_profile_export "GITHUB_AUTHENTICATION" "${GITHUB_AUTHENTICATION:-}"
append_profile_export "GEM_HOME" "/usr/local/bundle"
append_profile_export "BUNDLE_APP_CONFIG" "/usr/local/bundle"
append_profile_export "PATH" "/usr/local/bundle/bin:${PATH}"
if [ -n "${SECRET_KEY_BASE:-}" ]; then
  append_profile_export "SECRET_KEY_BASE" "${SECRET_KEY_BASE}"
fi
append_profile_export "RAILS_ENV" "${RAILS_ENV:-production}"
chown redmine:redmine "${REDMINE_PATH}/.profile" || true
chmod 600 "${REDMINE_PATH}/.profile" || true

echo "TZ=$TZ" >> /etc/default/cron



  echo "
export TZ=${TZ}

# Incoming emails API: Administration -> Settings -> Incoming email - API key
HELPDESK_EMAIL_KEY=${HELPDESK_EMAIL_KEY}
# Host for the helpdesk api from where to fetch support mails
TASKMAN_URL=${REDMINE_HOST}

T_EMAIL_HOST=${T_EMAIL_HOST}
T_EMAIL_PORT=${T_EMAIL_PORT}
T_EMAIL_USER=${T_EMAIL_USER}
T_EMAIL_PASS=${T_EMAIL_PASS}
T_EMAIL_FOLDER=Inbox
T_EMAIL_SSL=true

# EEA Entra ID application credentials
ENTRA_ID_TENANT_ID=${ENTRA_ID_TENANT_ID}
ENTRA_ID_CLIENT_ID=${ENTRA_ID_CLIENT_ID}
ENTRA_ID_CLIENT_SECRET=${ENTRA_ID_CLIENT_SECRET}

" > /etc/environment

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
diff /tmp/configuration.yml ${REDMINE_PATH}/config/configuration.yml
mv /tmp/configuration.yml ${REDMINE_PATH}/config/configuration.yml


# delete empty plugin artifacts only when the cache mount is writable
if [ -d "${PLUGIN_CACHE_DIR}" ] && [ -w "${PLUGIN_CACHE_DIR}" ]; then
  find "${PLUGIN_CACHE_DIR}" -size 0 -type f -exec rm {} \;
fi

for plugin in $(cat "${REDMINE_PATH}/plugins.cfg"); do
  plugin_name=$(echo "${plugin}" | cut -d':' -f1)
  plugin_file=$(echo "${plugin}" | cut -d':' -f2)
  plugin_archive=""

  if [ ! -d "${REDMINE_PATH}/plugins/${plugin_name}" ]; then
    # Always prefer already-mounted local caches (e.g. /install_plugins) so boot
    # works without remote credentials. Only download when runtime sync is enabled.
    if [ -f "${PLUGIN_CACHE_DIR}/${plugin_file}" ]; then
      plugin_archive="${PLUGIN_CACHE_DIR}/${plugin_file}"
    elif [ -f "${PLUGIN_FALLBACK_DIR}/${plugin_file}" ]; then
      plugin_archive="${PLUGIN_FALLBACK_DIR}/${plugin_file}"
    elif [ "${RUNTIME_PLUGIN_SYNC}" = "1" ] && [ -n "${PLUGINS_URL:-}" ]; then
      plugin_archive=$(resolve_archive "${PLUGIN_CACHE_DIR}/${plugin_file}" "${PLUGIN_FALLBACK_DIR}/${plugin_file}" "${PLUGINS_URL}/${plugin_file}" "${PLUGINS_USER:-}" "${PLUGINS_PASSWORD:-}" "plugin - ${plugin_file}")
    fi

    if [ -n "${plugin_archive}" ]; then
      echo "Found missing plugin - ${plugin_name}, will install it"
      unzip -d "${REDMINE_PATH}/plugins" -o "${plugin_archive}"
      REDMINE_PLUGINS_MIGRATE="yes"
      RUNTIME_ADDONS_CHANGED=1
    elif [ "${RUNTIME_PLUGIN_SYNC}" = "1" ] && [ -n "${PLUGINS_URL:-}" ]; then
      echo "Missing plugin archive for ${plugin_name} (${plugin_file}) even after sync attempt"
      exit 1
    else
      echo "Missing plugin ${plugin_name} (${plugin_file}) and runtime sync is disabled; keeping current startup mode."
    fi
  fi
done

if [ "${RUNTIME_PLUGIN_SYNC}" = "1" ] && [ -n "${PLUGINS_URL:-}" ]; then

  #remove old plugins only from writable caches
  if [ -d "${PLUGIN_CACHE_DIR}" ] && [ -w "${PLUGIN_CACHE_DIR}" ]; then
    for file in  ${PLUGIN_CACHE_DIR}/*; do 
      [ -e "$file" ] || continue
      if [ "$(grep ":${file/\/install_plugins\//}" ${REDMINE_PATH}/plugins.cfg | wc -l )" -eq 0 ]; then
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
A1_THEME_ZIP=${A1_THEME_ZIP:-a1_theme-4_1_2.zip}
A1_THEME_URL=${A1_THEME_URL:-}
A1_THEME_USER=${A1_THEME_USER:-${PLUGINS_USER:-}}
A1_THEME_PASSWORD=${A1_THEME_PASSWORD:-${PLUGINS_PASSWORD:-}}

if [ -z "${A1_THEME_URL}" ] && [ -n "${PLUGINS_URL:-}" ]; then
  A1_THEME_URL="${PLUGINS_URL%/plugins}/themes/${A1_THEME_ZIP}"
fi

if [ "${RUNTIME_THEME_SYNC}" = "1" ] && [ -n "${A1_THEME_URL}" ] && [ ! -d "${THEMES_DIR}/${A1_THEME_ID}" ]; then
  theme_archive=$(resolve_archive "${THEME_CACHE_DIR}/${A1_THEME_ZIP}" "${THEME_FALLBACK_DIR}/${A1_THEME_ZIP}" "${A1_THEME_URL}" "${A1_THEME_USER}" "${A1_THEME_PASSWORD}" "theme - ${A1_THEME_ZIP}")

  if [ -n "${A1_THEME_SHA256:-}" ]; then
    echo "${A1_THEME_SHA256}  ${theme_archive}" | sha256sum -c -
  fi

  unzip -d "${THEMES_DIR}" -o "${theme_archive}"
  RUNTIME_ADDONS_CHANGED=1
fi

if [ "${RUNTIME_ADDONS_CHANGED}" = "1" ] || ! bundle check >/dev/null 2>&1; then
  if [ "${FAST_BOOT}" != "1" ] && [ "${RUNTIME_BUNDLE_INSTALL}" = "1" ]; then
    echo "Installing runtime plugin/theme gem dependencies"
    bundle config set without 'development test' >/dev/null 2>&1
    bundle install
  else
    echo "Runtime gem installation is disabled (FAST_BOOT=${FAST_BOOT}, RUNTIME_BUNDLE_INSTALL=${RUNTIME_BUNDLE_INSTALL})."
    echo "Build a complete image with all gems/plugins/themes baked in, or set RUNTIME_BUNDLE_INSTALL=1 for legacy behavior."
    exit 1
  fi
fi

#ensure correct permissions
chown -R redmine:redmine /usr/src/redmine/plugins
chown -R redmine:redmine "${THEMES_DIR}"
chown redmine:redmine /usr/src/redmine/tmp

if [ -n "${REDMINE_DB_POOL:-}" ]; then
    sed -i "/bundle check/a\        echo '  pool: $REDMINE_DB_POOL' >> config\/database.yml"    /docker-entrypoint.sh
fi

/docker-entrypoint.sh rails server -b 0.0.0.0

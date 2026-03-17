#!/bin/bash

set -euo pipefail

REDMINE_PATH=${REDMINE_PATH:-/usr/src/redmine}

# Redmine 6 images may use ${REDMINE_PATH}/themes as the theme directory.
# Prefer it when present, otherwise fall back to the legacy public/themes path.
if [ -n "${REDMINE_THEMES_PATH:-}" ]; then
  REDMINE_THEMES_PATH="${REDMINE_THEMES_PATH}"
elif [ -d "${REDMINE_PATH}/themes" ]; then
  REDMINE_THEMES_PATH="${REDMINE_PATH}/themes"
else
  REDMINE_THEMES_PATH="${REDMINE_PATH}/public/themes"
fi

mkdir -p /install_plugins /install_themes

install_plugins_from_local_cache() {
  local cfg_file="${REDMINE_PATH}/addons.cfg"
  local manifest_script="${REDMINE_PATH}/config/lib/addons_manifest.rb"
  if [ ! -f "$cfg_file" ]; then
    echo "addons.cfg not found at $cfg_file (skipping RedmineUP plugins)"
    return 0
  fi
  if [ ! -f "$manifest_script" ]; then
    echo "addons manifest helper not found at $manifest_script"
    return 1
  fi

  local addons_base_url="${ADDONS_BASE_URL:-${PLUGINS_URL%/plugins}}"
  while IFS=: read -r kind plugin_name location plugin_file; do
    [ -n "$kind" ] || continue
    case "$kind" in
      \#*) continue ;;
    esac
    [ "$kind" = "plugin" ] || continue

    if [ -f "/install_plugins/$plugin_file" ]; then
      if [ ! -d "${REDMINE_PATH}/plugins/$plugin_name" ]; then
        echo "Installing plugin $plugin_name from /install_plugins/$plugin_file"
        unzip -d "${REDMINE_PATH}/plugins" -o "/install_plugins/$plugin_file"
        REDMINE_PLUGINS_MIGRATE="yes"
      fi
      continue
    fi

    if [ -n "${addons_base_url:-}" ]; then
      local full_url
      full_url=${addons_base_url/https:\/\//https:\/\/${PLUGINS_USER:-}:${PLUGINS_PASSWORD:-}@}
      echo "Missing /install_plugins/$plugin_file; downloading from ${addons_base_url}/${location}"
      wget -q -O "/install_plugins/$plugin_file" "$full_url/$location/$plugin_file"
      unzip -d "${REDMINE_PATH}/plugins" -o "/install_plugins/$plugin_file"
      REDMINE_PLUGINS_MIGRATE="yes"
      continue
    fi

    echo "Missing /install_plugins/$plugin_file and ADDONS_BASE_URL/PLUGINS_URL is empty; skipping $plugin_name"
  done < <(ruby "$manifest_script" list)

  if [[ "${REDMINE_PLUGINS_MIGRATE:-no}" == "yes" ]]; then
    touch "${REDMINE_PATH}/log/redmine_helpdesk.log" || true
    chown redmine:redmine "${REDMINE_PATH}/log/redmine_helpdesk.log" || true
    export REDMINE_PLUGINS_MIGRATE
  fi

  # Optional cleanup (disabled by default; also avoids failing on read-only mounts)
  if [[ "${CLEANUP_INSTALL_PLUGINS:-no}" == "yes" ]] && [ -w /install_plugins ]; then
    for file in /install_plugins/*; do
      [ -e "$file" ] || continue
      if [ "$(ruby "$manifest_script" has-plugin-archive "${file##*/}")" != "1" ]; then
        rm -f "$file"
      fi
    done
  fi
}

install_themes_from_local_cache() {
  if [ -d "${REDMINE_THEMES_PATH}" ]; then
    for z in /install_themes/*.zip; do
      [ -e "$z" ] || continue
      echo "Installing theme from $z into ${REDMINE_THEMES_PATH}"
      unzip -d "${REDMINE_THEMES_PATH}" -o "$z"
    done
  fi
}

install_plugins_from_local_cache
install_themes_from_local_cache


#patch
rm -f /usr/src/redmine/plugins/redmine_checklists/lib/redmine_checklists/patches/compatibility/application_controller_patch.rb
rm -f /usr/src/redmine/plugins/redmine_agile/lib/redmine_agile/patches/compatibility/application_controller_patch.rb

#patch for avatars_helper & wkhtmltopdf-binary
# NOTE: Do not delete avatars_helper_patch.rb; the plugin may still require it.
# If needed, disable it by removing the require line below.
# rm -f /usr/src/redmine/plugins/redmine_contacts_helpdesk/lib/redmine_helpdesk/patches/avatars_helper_patch.rb
if [ -f /usr/src/redmine/plugins/redmine_contacts_helpdesk/lib/redmine_helpdesk.rb ]; then
     sed -i "s#require 'redmine_helpdesk/patches/avatars_helper_patch'##" /usr/src/redmine/plugins/redmine_contacts_helpdesk/lib/redmine_helpdesk.rb
fi

#ensure correct permissions
chown -R redmine:redmine /usr/src/redmine/tmp /usr/src/redmine/plugins || true
chown -R redmine:redmine "${REDMINE_THEMES_PATH}" || true

export RAILS_ENV=${RAILS_ENV:-test}

apt-get update -q 
apt-get install -y --no-install-recommends build-essential 
apt-get clean
rm -rf /var/lib/apt/lists/* 

echo 'test:
  adapter: mysql2
  database: redmine_test
  host: mysql
  username: redmine
  password: password
  encoding: utf8mb4
' > /usr/src/redmine/config/database.yml


#prepare configuarion 
sed -i 's/BUNDLE_WITHOUT.*//' /usr/local/bundle/config
rm -f /usr/src/redmine/config/configuration.yml

echo 'gem "ci_reporter_minitest"' >> Gemfile
echo 'gem "minitest-reporters"' >> Gemfile



echo "
require 'ci/reporter/rake/minitest'
require 'minitest/reporters'

task :test => 'ci:setup:minitest'
namespace 'redmine' do
  namespace 'plugins' do
    task :test => 'ci:setup:minitest'
  end
end
namespace 'test' do
  task :system => 'ci:setup:minitest'
end
" >> Rakefile


#setup for selenium
mkdir -p /usr/src/redmine/test/fixtures/files/downloads
chmod -R 777 /usr/src/redmine/test
chmod -R 777 /usr/src/redmine/test/fixtures/files/downloads

sed -i "s#Rails.root,.*#Rails.root, 'test/fixtures/files/downloads'))#" test/application_system_test_case.rb 
sed -i 's#CSV.read.*#CSV.read("/usr/src/redmine/test/fixtures/files/downloads/issues.csv")#' test/system/issues_test.rb
sed -i '/CSV.read.*/i\    sleep 5' test/system/issues_test.rb
sed -i 's#sleep 0.2#sleep 1#' test/system/issues_test.rb
sed -i '/select#time_entry_activity_id/i\    sleep 3' test/system/timelog_test.rb
sed -i '/.*driven_by :selenium.*/a\      url: "http:\/\/hub:4444\/wd\/hub",' test/application_system_test_case.rb
sed -i '/.*chromeOptions.*/a\          "args" =>  %w[headless window-size=1024x900],' test/application_system_test_case.rb
sed -i '/.*setup do.*/a\    Capybara.server_host = "0.0.0.0"\n    Capybara.server = :puma, { Threads: "1:1" }\n    Capybara.app_host = "http:\/\/redmine:#{Capybara.current_session.server.port}"\n    host! "http:\/\/redmine:#{Capybara.current_session.server.port}"' test/application_system_test_case.rb


bundle install

mv plugins /tmp
bundle exec rake db:migrate
mv /tmp/plugins  /usr/src/redmine/


if [ -d /usr/src/redmine/plugins/redmine_contacts ]; then
        mv /usr/src/redmine/plugins/redmine_contacts /tmp/
fi

if [ -d /usr/src/redmine/plugins/redmine_contacts_helpdesk ]; then
        mv /usr/src/redmine/plugins/redmine_contacts_helpdesk /tmp/
fi


bundle exec rake redmine:plugins:migrate

if [ -d /tmp/redmine_contacts ]; then
      mv /tmp/redmine_contacts /usr/src/redmine/plugins
      bundle install
      bundle exec rake redmine:plugins:migrate
fi


if [ -d /tmp/redmine_contacts_helpdesk ]; then
      mv /tmp/redmine_contacts_helpdesk /usr/src/redmine/plugins
      bundle install
      bundle exec rake redmine:plugins:migrate
fi

# Start a Rails server if requested (useful for local interactive runs)
if [[ "${START_SERVER:-0}" == "1" ]]; then
  echo "Starting Redmine (Rails server) on 0.0.0.0:3000 (RAILS_ENV=${RAILS_ENV})"
  exec bundle exec ruby bin/rails server -b 0.0.0.0 -p 3000
fi

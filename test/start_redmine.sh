#!/bin/bash

mkdir -p /install_plugins

if [ ! -z "${PLUGINS_URL}" ]; then
  full_url=${PLUGINS_URL/https:\/\//https:\/\/$PLUGINS_USER:$PLUGINS_PASSWORD@}
  for plugin in $(cat ${REDMINE_PATH}/plugins.cfg); do
      
      plugin_name=$(echo $plugin | cut -d':' -f1)
      plugin_file=$(echo $plugin | cut -d':' -f2)

      if [ ! -f /install_plugins/$plugin_file ]; then
              echo "Found missing plugin - $plugin_file, will download and install it"
              wget -q -O  /install_plugins/$plugin_file $full_url/$plugin_file
              unzip -d ${REDMINE_PATH}/plugins -o /install_plugins/$plugin_file
              REDMINE_PLUGINS_MIGRATE="yes" 
     fi
     if [ ! -d ${REDMINE_PATH}/plugins/$plugin_name ]; then
            echo "Found missing plugin - $plugin_name, will install it"
            unzip -d ${REDMINE_PATH}/plugins -o /install_plugins/$plugin_file
            REDMINE_PLUGINS_MIGRATE="yes"
     fi   
  done

  #remove old plugins
  for file in  /install_plugins/*; do 
    if [ $(grep  ":${file/\/install_plugins\//}" ${REDMINE_PATH}/plugins.cfg | wc -l ) -eq 0 ]; then
         rm $file
    fi  
  done 

  if [[ $REDMINE_PLUGINS_MIGRATE == "yes" ]]; then
         touch ${REDMINE_PATH}/log/redmine_helpdesk.log
         chown redmine:redmine ${REDMINE_PATH}/log/redmine_helpdesk.log
         export REDMINE_PLUGINS_MIGRATE
  fi

fi


#patch
rm -f /usr/src/redmine/plugins/redmine_checklists/lib/redmine_checklists/patches/compatibility/application_controller_patch.rb
rm -f /usr/src/redmine/plugins/redmine_agile/lib/redmine_agile/patches/compatibility/application_controller_patch.rb

#patch for avatars_helper & wkhtmltopdf-binary
rm -f /usr/src/redmine/plugins/redmine_contacts_helpdesk/lib/redmine_helpdesk/patches/avatars_helper_patch.rb
if [ -f /usr/src/redmine/plugins/redmine_contacts_helpdesk/lib/redmine_helpdesk.rb ]; then
     sed -i "s#require 'redmine_helpdesk/patches/avatars_helper_patch'##" /usr/src/redmine/plugins/redmine_contacts_helpdesk/lib/redmine_helpdesk.rb
fi

#ensure correct permissions
chown -R redmine:redmine /usr/src/redmine/tmp /usr/src/redmine/plugins

export RAILS_ENV=test

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
mkdir /usr/src/redmine/test/fixtures/files/downloads
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


#remove from testing archived plugin
rm -rf /usr/src/redmine/plugins/redmine_ldap_sync



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



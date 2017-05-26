#!/bin/bash

if [ -d "/install_plugins" ]; then
   for i in /install_plugins/*.zip; do
       unzip -d ${REDMINE_PATH}/plugins -o $i
   done
   #install plugins dependencies
   /usr/local/bin/bundle install --without development test
   /usr/local/bin/bundle exec rake redmine:plugins:migrate
   chown redmine:redmine ${REDMINE_PATH}/log/redmine_helpdesk.log
fi
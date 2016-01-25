#!/bin/bash

REDMINE_PATH=/var/local/redmine
LOG_DIR=$REDMINE_PATH/log
/usr/local/bin/bundle exec rake -f $REDMINE_PATH/Rakefile --silent redmine:plugins:ldap_sync:sync_users RAILS_ENV="production" >> $LOG_DIR/ldap_sync.log 2>&1

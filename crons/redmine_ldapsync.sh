#!/bin/bash

REDMINE_PATH=/usr/src/redmine

if [[ -z "${LOG_FILE}" || ! -w "${LOG_FILE}" ]] ; then
  LOG_FILE=/proc/1/fd/1
fi

echo "ldapsync - $(/usr/local/bin/bundle exec rake -f $REDMINE_PATH/Rakefile --silent redmine:plugins:ldap_sync:sync_users RAILS_ENV="production")" >> $LOG_FILE 2>&1

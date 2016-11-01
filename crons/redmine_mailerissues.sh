#! /bin/bash

REDMINE_PATH=/var/local/redmine

if [[ -z "${LOG_FILE}" || ! -w "${LOG_FILE}" ]] ; then
  LOG_FILE=/proc/1/fd/1
fi

echo "mailerissues - $(/usr/local/bin/bundle exec rake -f $REDMINE_PATH/Rakefile reminder:exec RAILS_ENV="production")" >> $LOG_FILE 2>&1

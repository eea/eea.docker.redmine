#! /bin/bash

REDMINE_PATH=/var/local/redmine
LOG_DIR=$REDMINE_PATH/log

/usr/local/bin/bundle exec rake -f $REDMINE_PATH/Rakefile reminder:exec RAILS_ENV="production" >> $LOG_DIR/mailerissues.log 2>&1

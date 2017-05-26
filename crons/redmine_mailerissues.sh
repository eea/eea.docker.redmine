#!/bin/bash

REDMINE_PATH=/usr/src/redmine
echo "mailerissues - $(/usr/local/bin/bundle exec rake -f $REDMINE_PATH/Rakefile reminder:exec RAILS_ENV="production")"

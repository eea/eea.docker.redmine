#!/bin/bash

REDMINE_PATH=/usr/src/redmine
echo "ldapsync - $(/usr/local/bin/bundle exec rake -f $REDMINE_PATH/Rakefile redmine:plugins:ldap_sync:sync_users RAILS_ENV="production")"
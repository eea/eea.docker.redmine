#!/bin/bash

REDMINE_PATH=/usr/src/redmine

if [ -e /etc/environment ]; then
  source /etc/environment
fi

if [ -e $REDMINE_PATH/.profile ]; then
  source $REDMINE_PATH/.profile
fi

export GEM_HOME=/usr/local/bundle
export BUNDLE_APP_CONFIG=/usr/local/bundle
unset BUNDLE_PATH

cd $REDMINE_PATH
echo "ldapsync - "

/usr/local/bin/bundle exec rake -f $REDMINE_PATH/Rakefile redmine:plugins:ldap_sync:sync_users RAILS_ENV="production"

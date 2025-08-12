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

echo "email - "

# this adds a note to the existing issue if you reply to it from your email
# this creates a new issue in the it-helpdesk project if subject does not contain the issue

/usr/local/bin/bundle exec rake -f $REDMINE_PATH/Rakefile redmine:email:receive_imap RAILS_ENV="production" \
host=$T_EMAIL_HOST username=$T_EMAIL_USER password=$T_EMAIL_PASS ssl=$T_EMAIL_SSL port=$T_EMAIL_PORT folder=$T_EMAIL_FOLDER \
project=it-helpdesk move_on_success=read move_on_failure=failed \
allow_override=project,tracker,priority,status,category,fixed_version

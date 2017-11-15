#!/bin/bash


REDMINE_PATH=/usr/src/redmine

if [ -e /var/local/environment/vars ]; then
  source /var/local/environment/vars
fi

if [ -e $REDMINE_PATH/.profile ]; then
  source $REDMINE_PATH/.profile
fi



cd $REDMINE_PATH


echo "$(date) - helpdesk - $(wget -O - $TASKMAN_URL/helpdesk_mailer/get_mail?key=$HELPDESK_EMAIL_KEY)"

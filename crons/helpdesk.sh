#!/bin/bash

if [ -e /var/local/environment/vars ]; then
  source /var/local/environment/vars
fi

echo "$(date) - helpdesk - $(wget -O - $TASKMAN_URL/helpdesk_mailer/get_mail?key=$HELPDESK_EMAIL_KEY)"

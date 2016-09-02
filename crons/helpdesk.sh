#!/bin/bash
source /var/local/environment/vars
echo "$(date) - $(wget -O - https://taskman.eionet.europa.eu/helpdesk_mailer/get_mail?key=$HELPDESK_EMAIL_KEY)" >> /home/redmine/redmine/log/helpdesk_cron.log

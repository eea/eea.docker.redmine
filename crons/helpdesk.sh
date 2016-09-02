#!/bin/bash
source /var/local/environment/vars
wget -O - https://taskman.eionet.europa.eu/helpdesk_mailer/get_mail?key=$HELPDESK_EMAIL_KEY >> /var/local/redmine/log/helpdesk_cron.log

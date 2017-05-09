#!/bin/bash

if [ -e /var/local/environment/vars ]; then
  source /var/local/environment/vars
fi

if [[ -z "${LOG_FILE}" || ! -w "${LOG_FILE}" ]] ; then
  LOG_FILE=/proc/1/fd/1
fi

echo "$(date) - helpdesk - $(wget -O - https://taskman.eionet.europa.eu/helpdesk_mailer/get_mail?key=$HELPDESK_EMAIL_KEY)" >> $LOG_FILE 2>&1

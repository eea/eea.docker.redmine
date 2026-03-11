#!/bin/bash


REDMINE_PATH=/usr/src/redmine

if [ -e /etc/environment ]; then
  source /etc/environment
fi

if [ -e $REDMINE_PATH/.profile ]; then
  source $REDMINE_PATH/.profile
fi



cd $REDMINE_PATH


TASKMAN_URL=${TASKMAN_URL:-http://127.0.0.1:3000}
HELPDESK_URL="${TASKMAN_URL%/}/helpdesk_mailer/get_mail?key=${HELPDESK_EMAIL_KEY}"

if command -v wget >/dev/null 2>&1; then
  RESULT="$(wget -q -T 20 -O - "${HELPDESK_URL}" 2>&1)"
else
  RESULT="$(curl -fsS --max-time 20 "${HELPDESK_URL}" 2>&1)"
fi

echo "$(date) - helpdesk - ${RESULT}"

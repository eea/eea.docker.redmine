#!/bin/bash

service rsyslog restart
service cron restart

echo "export SYNC_API_KEY=$SYNC_API_KEY"  >> ${REDMINE_PATH}/.profile
echo "export SYNC_REDMINE_URL=$SYNC_REDMINE_URL"  >> ${REDMINE_PATH}/.profile 
echo "TZ=$TZ" >> /etc/default/cron

/docker-entrypoint.sh rails server -b 0.0.0.0



#!/bin/bash
set -e

# Add env to cronjobs
if [ ! -z "$SYNC_API_KEY" ]; then
  sed -i "s|API_KEY|$SYNC_API_KEY|" ${REDMINE_LOCAL_PATH}/crons/cronjobs
else
  sed -i "s|-k API_KEY||" ${REDMINE_LOCAL_PATH}/crons/cronjobs
fi

# Start crond
crontab -u redmine ${REDMINE_LOCAL_PATH}/crons/cronjobs
cron

# Run redmine entry-point
exec /redmine-entrypoint.sh "$@"

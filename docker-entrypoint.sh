#!/bin/bash
set -e

# Start crond
cron

# Run redmine entry-point
exec /redmine-entrypoint.sh "$@"

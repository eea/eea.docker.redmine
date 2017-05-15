#!/bin/sh
cd /var/local/redmine
python crons/redmine.py -o github -k SYNC_API_KEY -r SYNC_REDMINE_URL -g SYNC_GITHUB_URL > /dev/null 2>&1

#!/bin/sh

REDMINE_PATH=/usr/src/redmine

if [ -e $REDMINE_PATH/.profile ]; then
  . $REDMINE_PATH/.profile
fi

cd /var/local/redmine
python3 crons/redmine.py -o github

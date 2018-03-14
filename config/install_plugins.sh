#!/bin/bash

if [ -d "/install_plugins" ]; then
   for i in /install_plugins/*.zip; do
       unzip -d ${REDMINE_PATH}/plugins -o $i
   done
   touch ${REDMINE_PATH}/log/redmine_helpdesk.log
   chown redmine:redmine ${REDMINE_PATH}/log/redmine_helpdesk.log
fi

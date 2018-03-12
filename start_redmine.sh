#!/bin/bash

service rsyslog restart
service cron restart

echo "export SYNC_API_KEY=$SYNC_API_KEY"  >> ${REDMINE_PATH}/.profile
echo "export SYNC_REDMINE_URL=$SYNC_REDMINE_URL"  >> ${REDMINE_PATH}/.profile 
echo "TZ=$TZ" >> /etc/default/cron

if [ ! -z "${T_EMAIL_HOST}" ]; then

  echo "
# Taskman email configuration
T_EMAIL_HOST=${T_EMAIL_HOST}
T_EMAIL_PORT=${T_EMAIL_PORT}
T_EMAIL_USER=${T_EMAIL_USER}
T_EMAIL_PASS=${T_EMAIL_PASS}
T_EMAIL_FOLDER=Inbox
T_EMAIL_SSL=true

# Incoming emails API: Administration -> Settings -> Incoming email - API key
HELPDESK_EMAIL_KEY=${INCOMING_MAIL_API_KEY}
# Host for the helpdesk api from where to fetch support mails
TASKMAN_URL=${REDMINE_HOST}

# Helpdesk email configuration
H_EMAIL_HOST=${H_EMAIL_HOST}
H_EMAIL_PORT=${H_EMAIL_PORT}
H_EMAIL_USER=${H_EMAIL_USER}
H_EMAIL_PASS=${H_EMAIL_PASS}
H_EMAIL_FOLDER=Inbox
H_EMAIL_SSL=false" > cat /var/local/environment/vars
fi

if [ ! -z "${PLUGINS_URL}" ]; then
  run_install=0
  for plugin in $(cat ${REDMINE_PATH}/plugins.cfg); do
   if [ ! -f /install_plugins/$plugin ]; then
      full_url=${PLUGINS_URL/https:\/\//https:\/\/$PLUGINS_USER:$PLUGINS_PASSWORD@}
      wget -O  /install_plugins/$plugin $full_url/$plugin
     run_install=1
   fi
  done

  #remove old plugins
  for file in  /install_plugins/*; do 
    if [ $(grep  ${file/\/install_plugins\//} ${REDMINE_PATH}/plugins.cfg | wc -l ) -eq 0 ]; then
         rm $file
    fi
  done 

  if [ $run_install -eq 1 ]; then
     ${REDMINE_PATH}/install_plugins.sh
  fi

fi



/docker-entrypoint.sh rails server -b 0.0.0.0



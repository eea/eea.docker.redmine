#!/bin/bash

touch /etc/crontab /etc/cron.*/* 
crontab /var/redmine_jobs.txt 
chmod 600 /etc/crontab  


service rsyslog restart
service cron restart

echo "export SYNC_API_KEY=$SYNC_API_KEY"  >> ${REDMINE_PATH}/.profile
echo "export SYNC_REDMINE_URL=$SYNC_REDMINE_URL"  >> ${REDMINE_PATH}/.profile 
echo "TZ=$TZ" >> /etc/default/cron

if [ ! -z "${T_EMAIL_HOST}" ]; then

  mkdir -p /var/local/environment

  echo "
# Taskman email configuration
T_EMAIL_HOST=${T_EMAIL_HOST}
T_EMAIL_PORT=${T_EMAIL_PORT}
T_EMAIL_USER=${T_EMAIL_USER}
T_EMAIL_PASS=${T_EMAIL_PASS}
T_EMAIL_FOLDER=Inbox
T_EMAIL_SSL=true

# Incoming emails API: Administration -> Settings -> Incoming email - API key
HELPDESK_EMAIL_KEY=${HELPDESK_EMAIL_KEY}
# Host for the helpdesk api from where to fetch support mails
TASKMAN_URL=${REDMINE_HOST}

# Helpdesk email configuration
H_EMAIL_HOST=${H_EMAIL_HOST}
H_EMAIL_PORT=${H_EMAIL_PORT}
H_EMAIL_USER=${H_EMAIL_USER}
H_EMAIL_PASS=${H_EMAIL_PASS}
H_EMAIL_FOLDER=Inbox
H_EMAIL_SSL=false" > /var/local/environment/vars
fi

if [ ! -z "${PLUGINS_URL}" ]; then
  run_install=0
  read_conf=0
  for plugin_conf in $(cat ${REDMINE_PATH}/plugins.cfg); do
      read_conf=$(( $read_conf + 1 ))  
      if  (( read_conf % 2 )); then
          if [ ! -d ${REDMINE_PATH}/plugins/$plugin_conf ]; then
            echo "Found missing plugin - $plugin_conf, will install it"
            run_install=1
         fi   
      else
          if [ ! -f /install_plugins/$plugin_conf ]; then
              echo "Found missing plugin - $plugin_conf, will download and install it"
              full_url=${PLUGINS_URL/https:\/\//https:\/\/$PLUGINS_USER:$PLUGINS_PASSWORD@}
              wget -O  /install_plugins/$plugin_conf $full_url/$plugin_conf
              run_install=1
          fi
      fi
  done

  #remove old plugins
  for file in  /install_plugins/*; do 
    if [ $(grep  ${file/\/install_plugins\//} ${REDMINE_PATH}/plugins.cfg | wc -l ) -eq 0 ]; then
         rm $file
    fi
    
    if [ ! -d ${REDMINE_PATH}/plugins/$(echo $plugin | cut -d'-' -f1) ]; then
         run_install=1
    fi
  done 

  if [ $run_install -eq 1 ]; then
     ${REDMINE_PATH}/install_plugins.sh
     export REDMINE_PLUGINS_MIGRATE=yes
  fi

fi





/docker-entrypoint.sh rails server -b 0.0.0.0



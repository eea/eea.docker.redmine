#!/bin/bash

touch /etc/crontab /etc/cron.*/* 
if [ -n "$RESTART_CRON" ] && [ $(grep -c 'rails server' /var/redmine_jobs.txt) -eq 0 ] ; then
	echo "${RESTART_CRON} kill -2 \$(ps -fu redmine | grep 'rails server' | grep -v grep | awk '{print \$2}')" >> /var/redmine_jobs.txt
fi	
crontab /var/redmine_jobs.txt 
chmod 600 /etc/crontab  


service rsyslog restart
service cron restart

echo "export SYNC_API_KEY=$SYNC_API_KEY"  >> ${REDMINE_PATH}/.profile
echo "export SYNC_REDMINE_URL=$SYNC_REDMINE_URL"  >> ${REDMINE_PATH}/.profile 
echo "export GITHUB_AUTHENTICATION=$GITHUB_AUTHENTICATION"  >> ${REDMINE_PATH}/.profile
echo "export GEM_HOME=/usr/local/bundle"
echo "export BUNDLE_APP_CONFIG=/usr/local/bundle"
echo "export PATH=/usr/local/bundle/bin:$PATH"

echo "TZ=$TZ" >> /etc/default/cron

if [ -n "${T_EMAIL_HOST}" ]; then

  mkdir -p /var/local/environment

  echo "
export TZ=${TZ}

# Incoming emails API: Administration -> Settings -> Incoming email - API key
HELPDESK_EMAIL_KEY=${HELPDESK_EMAIL_KEY}
# Host for the helpdesk api from where to fetch support mails
TASKMAN_URL=${REDMINE_HOST}

T_EMAIL_HOST=${T_EMAIL_HOST}
T_EMAIL_PORT=${T_EMAIL_PORT}
T_EMAIL_USER=${T_EMAIL_USER}
T_EMAIL_PASS=${T_EMAIL_PASS}
T_EMAIL_FOLDER=Inbox
T_EMAIL_SSL=true


" > /var/local/environment/vars
fi

REDMINE_SMTP_HOST=${REDMINE_SMTP_HOST:-postfix}
REDMINE_SMTP_PORT=${REDMINE_SMTP_PORT:-25}
REDMINE_SMTP_DOMAIN=${REDMINE_SMTP_DOMAIN:-eionet.europa.eu}
REDMINE_SMTP_STARTTLSAUTO=${REDMINE_SMTP_STARTTLSAUTO:-true}

first_line=$(awk '/smtp_settings/ {print FNR}' ${REDMINE_PATH}/config/configuration.yml)
head -n ${first_line} ${REDMINE_PATH}/config/configuration.yml > /tmp/configuration.yml
if [[ "${REDMINE_SMTP_TLS}" == "false" ]]; then
  echo "      enable_starttls_auto: ${REDMINE_SMTP_STARTTLSAUTO}
      address: \"${REDMINE_SMTP_HOST}\"
      port: ${REDMINE_SMTP_PORT}
      domain: \"${REDMINE_SMTP_DOMAIN}\"
      tls: false" >> /tmp/configuration.yml
else
  echo "      enable_starttls_auto: ${REDMINE_SMTP_STARTTLSAUTO}
      address: \"${REDMINE_SMTP_HOST}\"
      port: ${REDMINE_SMTP_PORT}
      domain: \"${REDMINE_SMTP_DOMAIN}\"
" >> /tmp/configuration.yml
fi

last_line=$(sed -n '/smtp_settings/,/^$/p' ${REDMINE_PATH}/config/configuration.yml | wc -l )
let last_part=${first_line}+${last_line}-1
tail --lines=+$last_part ${REDMINE_PATH}/config/configuration.yml >> /tmp/configuration.yml
diff /tmp/configuration.yml ${REDMINE_PATH}/config/configuration.yml
mv /tmp/configuration.yml ${REDMINE_PATH}/config/configuration.yml


#delete empty plugins
find  /install_plugins -size 0 -type f -exec rm {} \;

if [ ! -z "${PLUGINS_URL}" ]; then
  full_url=${PLUGINS_URL/https:\/\//https:\/\/$PLUGINS_USER:$PLUGINS_PASSWORD@}
  for plugin in $(cat ${REDMINE_PATH}/plugins.cfg); do
      
      plugin_name=$(echo $plugin | cut -d':' -f1)
      plugin_file=$(echo $plugin | cut -d':' -f2)

      if [ ! -f /install_plugins/$plugin_file ]; then
              echo "Found missing plugin - $plugin_file, will download and install it"
              wget -q -O  /install_plugins/$plugin_file $full_url/$plugin_file
              unzip -d ${REDMINE_PATH}/plugins -o /install_plugins/$plugin_file
              REDMINE_PLUGINS_MIGRATE="yes" 
     fi
     if [ ! -d ${REDMINE_PATH}/plugins/$plugin_name ]; then
            echo "Found missing plugin - $plugin_name, will install it"
            unzip -d ${REDMINE_PATH}/plugins -o /install_plugins/$plugin_file
            REDMINE_PLUGINS_MIGRATE="yes"
     fi   
  done

  #remove old plugins
  for file in  /install_plugins/*; do 
    if [ $(grep  ":${file/\/install_plugins\//}" ${REDMINE_PATH}/plugins.cfg | wc -l ) -eq 0 ]; then
         rm $file
    fi  
  done 

  if [[ $REDMINE_PLUGINS_MIGRATE == "yes" ]]; then
         touch ${REDMINE_PATH}/log/redmine_helpdesk.log
         chown redmine:redmine ${REDMINE_PATH}/log/redmine_helpdesk.log
         export REDMINE_PLUGINS_MIGRATE
  fi

fi

#ensure correct permissions
chown -R redmine:redmine /usr/src/redmine/plugins
chown redmine:redmine /usr/src/redmine/tmp

if [ -n "$REDMINE_DB_POOL" ]; then
    sed -i "/bundle check/a\        echo '  pool: $REDMINE_DB_POOL' >> config\/database.yml"    /docker-entrypoint.sh
fi

/docker-entrypoint.sh rails server -b 0.0.0.0



#!/bin/bash

while ! nc -vz -w 3 $MYSQL_PORT_3306_TCP_ADDR $MYSQL_PORT_3306_TCP_PORT; do sleep 1; done
if [ -d "/install_plugins" ]; then
   for i in /install_plugins/*.zip; do 
       unzip -d ${REDMINE_INSTALL_DIR}/plugins -o $i
       #install plugins dependencies
       /usr/local/bin/bundle install --without development test
   done
fi
sudo -HE /sbin/entrypoint.sh app:start

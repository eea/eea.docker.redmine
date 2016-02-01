#!/bin/bash

while ! nc -vz -w 3 $MYSQL_PORT_3306_TCP_ADDR $MYSQL_PORT_3306_TCP_PORT; do sleep 1; done

sudo -HE /sbin/entrypoint.sh app:init
/usr/local/bin/bundle exec unicorn_rails -E ${RAILS_ENV} -c ${REDMINE_INSTALL_DIR}/config/unicorn.rb

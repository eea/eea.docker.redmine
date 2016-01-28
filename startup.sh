#!/bin/bash
sudo -HE /sbin/entrypoint.sh app:init
/usr/local/bin/bundle exec unicorn_rails -E ${RAILS_ENV} -c ${REDMINE_INSTALL_DIR}/config/unicorn.rb

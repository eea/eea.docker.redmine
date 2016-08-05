#!/bin/bash

if [ -d "/install_plugins" ]; then
   for i in /install_plugins/*.zip; do
       unzip -d ${REDMINE_INSTALL_DIR}/plugins -o $i
       #install plugins dependencies
       /usr/local/bin/bundle install --without development test
   done
fi

# adding sync scripts
svn co https://svn.eionet.europa.eu/repositories/Zope/trunk/www.eea.europa.eu/trunk/tools/redmine /home/redmine/redmine/github

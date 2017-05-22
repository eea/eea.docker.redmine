#!/bin/bash

REDMINE_PATH=/usr/src/redmine

if [[ -z "${LOG_FILE}" || ! -w "${LOG_FILE}" ]] ; then
  LOG_FILE=/proc/1/fd/1
fi

cd $REDMINE_PATH

export PATH=/usr/local/bin:$PATH
export GEM_HOME=/usr/local/bundle
export GEM_PATH=/usr/local/bundle/gems:/usr/local/lib/ruby/gems/2.2.0
export BUNDLE_APP_CONFIG=/usr/local/bundle
export BUNDLE_BIN=/usr/local/bundle/bin
export BUNDLE_PATH=/usr/local/bundle

echo "mailerissues - $(bin/rake -f Rakefile reminder:exec[test] RAILS_ENV=production)" >> $LOG_FILE 2>&1
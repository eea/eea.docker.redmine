#!/bin/bash
set -euo pipefail

REDMINE_PATH=/usr/src/redmine
JOB_CLASS="${1:-}"
LOCK_NAME="${2:-}"

if [ -z "${JOB_CLASS}" ] || [ -z "${LOCK_NAME}" ]; then
  echo "Usage: $0 <job_class> <lock_name>"
  exit 1
fi

if [ -e /etc/environment ]; then
  # shellcheck disable=SC1091
  source /etc/environment
fi

if [ -e "${REDMINE_PATH}/.profile" ]; then
  # shellcheck disable=SC1091
  source "${REDMINE_PATH}/.profile"
fi

export GEM_HOME=/usr/local/bundle
export BUNDLE_APP_CONFIG=/usr/local/bundle
unset BUNDLE_PATH

cd "${REDMINE_PATH}"

RAILS_ENV="${RAILS_ENV:-production}" \
RAILS_PULSE_JOB="${JOB_CLASS}" \
RAILS_PULSE_LOCK="${LOCK_NAME}" \
bundle exec rails runner '
  job_name = ENV.fetch("RAILS_PULSE_JOB")
  lock_name = ENV.fetch("RAILS_PULSE_LOCK")
  conn = ActiveRecord::Base.connection
  quoted_lock = conn.quote(lock_name)
  got_lock = conn.select_value("SELECT GET_LOCK(#{quoted_lock}, 0)").to_i == 1

  unless got_lock
    puts "rails_pulse_job skip lock=#{lock_name}"
    exit 0
  end

  begin
    klass = Object.const_get(job_name)
    klass.perform_now
    puts "rails_pulse_job ok job=#{job_name} lock=#{lock_name}"
  ensure
    conn.select_value("SELECT RELEASE_LOCK(#{quoted_lock})")
  end
'

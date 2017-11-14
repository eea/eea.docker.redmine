#!/bin/bash

service rsyslog restart
service cron restart

/docker-entrypoint.sh rails server -b 0.0.0.0



#!/bin/bash

REDMINE_PATH=/var/local/redmine

cd ${REDMINE_PATH}/github/ && python redmine.py > /dev/null 2>&1

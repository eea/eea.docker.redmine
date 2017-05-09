#!/bin/bash

REDMINE_GITHUB_PATH=/var/local/redmine/github/

cd ${REDMINE_GITHUB_PATH}/github/ && python redmine.py > /dev/null 2>&1

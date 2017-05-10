FROM redmine:3.3.0
LABEL maintainer="EEA: IDM2 A-Team <eea-edw-a-team-alerts@googlegroups.com>"

ENV REDMINE_PATH=/usr/src/redmine \
    REDMINE_LOCAL_PATH=/var/local/redmine

#install eea cron tools
COPY crons/ ${REDMINE_LOCAL_PATH}/crons

# install dependencies and plugins
RUN apt-get update -q \
 && apt-get install -y --no-install-recommends cron graphviz vim nano mc \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p ${REDMINE_LOCAL_PATH}/github \
 && git clone -b RELEASE_0_7_0 https://github.com/tckz/redmine-wiki_graphviz_plugin.git ${REDMINE_PATH}/plugins/wiki_graphviz_plugin \
 && git clone -b Ver_0.3.0 https://github.com/masamitsu-murase/redmine_add_subversion_links.git ${REDMINE_PATH}/plugins/redmine_add_subversion_links \
 && git clone -b v2.2.0 https://github.com/koppen/redmine_github_hook.git ${REDMINE_PATH}/plugins/redmine_github_hook \
 && git clone -b 0.0.2 https://github.com/bluezio/redmine_wiki_backlinks.git ${REDMINE_PATH}/plugins/redmine_wiki_backlinks \
 && git clone https://github.com/Hopebaytech/redmine_mail_reminder.git ${REDMINE_PATH}/plugins/redmine_mail_reminder \
 && cd ${REDMINE_PATH}/plugins/redmine_mail_reminder \
 && git checkout 394ec7cefa6ba2ab6865fb15b694e23b3b9aeda9 \
 && cd .. \
 && git clone https://github.com/thorin/redmine_ldap_sync.git ${REDMINE_PATH}/plugins/redmine_ldap_sync \
 && cd ${REDMINE_PATH}/plugins/redmine_ldap_sync \
 && git checkout 66b23e9cc311a1dc8e4a928feaa0c3a6f631764a \
 && cd .. \
 && git clone https://github.com/eea/eea.redmine.theme.git ${REDMINE_PATH}/public/themes/eea.redmine.theme \
 && chown -R redmine:redmine ${REDMINE_PATH} ${REDMINE_LOCAL_PATH} \
 && crontab -u redmine ${REDMINE_LOCAL_PATH}/crons/cronjobs \
 && mv /docker-entrypoint.sh /redmine-entrypoint.sh

COPY docker-entrypoint.sh /

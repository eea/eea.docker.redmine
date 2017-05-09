FROM redmine:3.3.0

MAINTAINER "European Environment Agency (EEA): IDM2 A-Team" <eea-edw-a-team-alerts@googlegroups.com>

ENV REDMINE_PATH /usr/src/redmine
ENV REDMINE_USER redmine
ENV REDMINE_GITHUB_PATH /var/local/redmine/github/

# install dependencies
RUN apt-get update -q && \
    apt-get install -y --no-install-recommends cron graphviz vim nano mc && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
    # ln -s ${WORKDIR} /var/local/redmine

USER redmine

RUN git clone -b RELEASE_0_7_0 https://github.com/tckz/redmine-wiki_graphviz_plugin.git ${REDMINE_PATH}/plugins/wiki_graphviz_plugin && \
    git clone -b Ver_0.3.0 https://github.com/masamitsu-murase/redmine_add_subversion_links.git ${REDMINE_PATH}/plugins/redmine_add_subversion_links && \
    git clone -b v2.2.0 https://github.com/koppen/redmine_github_hook.git ${REDMINE_PATH}/plugins/redmine_github_hook && \
    # "Wiki Backlinks" plugin
    git clone -b 0.0.2 https://github.com/bluezio/redmine_wiki_backlinks.git ${REDMINE_PATH}/plugins/redmine_wiki_backlinks && \
    # "Issue Reminder" plugin
    git clone https://github.com/Hopebaytech/redmine_mail_reminder.git ${REDMINE_PATH}/plugins/redmine_mail_reminder && \
    cd ${REDMINE_PATH}/plugins/redmine_mail_reminder && \
    git checkout 394ec7cefa6ba2ab6865fb15b694e23b3b9aeda9 && \
    cd .. && \
    # "LDAP sync" plugin
    git clone https://github.com/thorin/redmine_ldap_sync.git ${REDMINE_PATH}/plugins/redmine_ldap_sync && \
    cd ${REDMINE_PATH}/plugins/redmine_ldap_sync && \
    git checkout 66b23e9cc311a1dc8e4a928feaa0c3a6f631764a && \
    cd .. && \
    #install the theme
    git clone https://github.com/eea/eea.redmine.theme.git ${REDMINE_PATH}/public/themes/eea.redmine.theme && \
    chown -R ${REDMINE_USER}: ${REDMINE_PATH}/plugins ${REDMINE_PATH}/public/themes

#install eea cron tools and start services
ADD crons/ ${REDMINE_PATH}/crons
ADD sync_github/ ${REDMINE_GITHUB_PATH}

USER root

RUN chmod +x ${REDMINE_PATH}/crons/* && \
    chown -R ${REDMINE_USER}: ${REDMINE_PATH}/crons && \
    crontab -u ${REDMINE_USER} ${REDMINE_PATH}/crons/cronjobs && rm -rf ${REDMINE_PATH}/crons/cronjobs

FROM docker.io/sameersbn/redmine:3.3.0-1

MAINTAINER "European Environment Agency (EEA): IDM2 A-Team" <eea-edw-a-team-alerts@googlegroups.com>

#default for ENV vars
ENV DB_NAME=redmine_production \
    DB_USER=redmine \
    DB_PASS=password
    
ENV REDMINE_USER_UID=500 \
    REDMINE_USER_GID=500
    
ENV REDMINE_LOG_DIR="${REDMINE_HOME}/log"

ADD overrides/build/ ${REDMINE_BUILD_DIR}/
ADD overrides/runtime/ ${REDMINE_RUNTIME_DIR}/
ADD overrides/entrypoint.sh /sbin/entrypoint.sh
ADD chaperone.conf /etc/chaperone.d/chaperone.conf
ADD initialize_redmine.sh ${REDMINE_INSTALL_DIR}/initialize_redmine.sh

# Change redmine USERMAP
RUN bash ${REDMINE_BUILD_DIR}/install.sh && \
    chown -R ${REDMINE_USER} /etc/supervisor && \
    usermod -u ${REDMINE_USER_UID} ${REDMINE_USER} && \
    groupmod -g ${REDMINE_USER_GID} ${REDMINE_USER} && \ 
    usermod -aG sudo ${REDMINE_USER} && \
    find ${REDMINE_HOME} -path ${REDMINE_DATA_DIR}/\* -prune -o -print0 | xargs -0 chown -h ${REDMINE_USER}: && \
    usermod -g ${REDMINE_USER_GID} ${REDMINE_USER} 

# install dependencies
RUN apt-get update -q && \
    apt-get upgrade -y libc6 && \ 
    apt-get install -y --no-install-recommends git subversion graphviz python3-dev python3-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    pip3 install chaperone && \
    ln -s ${REDMINE_INSTALL_DIR} /var/local/redmine

#install plugins
RUN git clone https://github.com/tckz/redmine-wiki_graphviz_plugin.git plugins/wiki_graphviz_plugin && \
    git clone https://github.com/masamitsu-murase/redmine_add_subversion_links.git plugins/redmine_add_subversion_links && \
    git clone git://github.com/koppen/redmine_github_hook plugins/redmine_github_hook && \
    # "Wiki Backlinks" plugin
    git clone https://github.com/bluezio/redmine_wiki_backlinks.git plugins/redmine_wiki_backlinks && \
    # "Issue Reminder" plugin
    git clone https://github.com/Hopebaytech/redmine_mail_reminder.git plugins/redmine_mail_reminder && \
    # "LDAP sync" plugin
    git clone https://github.com/thorin/redmine_ldap_sync.git plugins/redmine_ldap_sync && \
    # "HelpDesk" plugin
    git clone git://github.com/eea/redmine_helpdesk.git plugins/redmine_helpdesk && \
    # workaround to don't have as dependency the codeclimate-test-reporter gem
    echo > plugins/redmine_helpdesk/Gemfile && \
    #install the theme
    git clone git://github.com/eea/eea.redmine.theme.git public/themes/eea.redmine.theme && \
    chown -R ${REDMINE_USER}: plugins public/themes && \
    cd ${REDMINE_INSTALL_DIR} && su ${REDMINE_USER} -c "bundle install"

#install eea cron tools and start services
ADD crons/ ${REDMINE_INSTALL_DIR}/crons

RUN chmod +x ${REDMINE_INSTALL_DIR}/initialize_redmine.sh && \
    chown ${REDMINE_USER}: ${REDMINE_INSTALL_DIR}/initialize_redmine.sh && \
    chmod +x ${REDMINE_INSTALL_DIR}/crons/* && \
    chown -R ${REDMINE_USER}: ${REDMINE_INSTALL_DIR}/crons && \
    crontab -u ${REDMINE_USER} ${REDMINE_INSTALL_DIR}/crons/cronjobs && rm -rf ${REDMINE_INSTALL_DIR}/crons/cronjobs

USER ${REDMINE_USER}

ENTRYPOINT ["/usr/local/bin/chaperone"]
CMD []

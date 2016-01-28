FROM docker.io/sameersbn/redmine:3.2.0-3

MAINTAINER Luca Pisani <luca.pisani@abstract.it>

#default for ENV vars
ENV DB_NAME=redmine_production \
    DB_USER=redmine \
    DB_PASS=password
    
ENV REDMINE_USER_UID=500 \
    REDMINE_USER_GID=500
    
ENV REDMINE_LOG_DIR="${REDMINE_HOME}/log"

COPY scripts/build/ ${REDMINE_BUILD_DIR}/
RUN bash ${REDMINE_BUILD_DIR}/install.sh
COPY scripts/runtime/ ${REDMINE_RUNTIME_DIR}/

# Change redmine USERMAP
RUN usermod -u ${REDMINE_USER_UID} ${REDMINE_USER}    
RUN groupmod -g ${REDMINE_USER_GID} ${REDMINE_USER}
RUN usermod -aG sudo ${REDMINE_USER}
RUN find ${REDMINE_HOME} -path ${REDMINE_DATA_DIR}/\* -prune -o -print0 | xargs -0 chown -h ${REDMINE_USER}:
RUN usermod -g ${REDMINE_USER_GID} ${REDMINE_USER} 

# install dependencies
RUN apt-get update -q && \
    apt-get install -y --no-install-recommends git subversion graphviz python3-dev python3-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    pip3 install chaperone

RUN ln -s ${REDMINE_INSTALL_DIR} /var/local/redmine

#install the plugins
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
    chown -R ${REDMINE_USER}: plugins public/themes

#install plugins dependencies
RUN cd ${REDMINE_INSTALL_DIR} && su ${REDMINE_USER} -c "bundle install"
COPY chaperone.conf /etc/chaperone.d/chaperone.conf

#install eea cron tools and start services
ADD startup.sh ${REDMINE_INSTALL_DIR}/startup.sh
RUN chmod +x ${REDMINE_INSTALL_DIR}/startup.sh && \
    chown ${REDMINE_USER}: ${REDMINE_INSTALL_DIR}/startup.sh

ADD setup_repo.sh ${REDMINE_INSTALL_DIR}/setup_repo.sh
RUN chmod +x ${REDMINE_INSTALL_DIR}/setup_repo.sh && \
    chown ${REDMINE_USER}: ${REDMINE_INSTALL_DIR}/setup_repo.sh
    
ADD helpdesk.sh ${REDMINE_INSTALL_DIR}/helpdesk.sh
RUN chmod +x ${REDMINE_INSTALL_DIR}/helpdesk.sh && \
    chown ${REDMINE_USER}: ${REDMINE_INSTALL_DIR}/helpdesk.sh

ADD taskman_email.sh ${REDMINE_INSTALL_DIR}/taskman_email.sh
RUN chmod +x ${REDMINE_INSTALL_DIR}/taskman_email.sh && \
    chown ${REDMINE_USER}: ${REDMINE_INSTALL_DIR}/taskman_email.sh

ADD redmine_ldapsync.sh ${REDMINE_INSTALL_DIR}/redmine_ldapsync.sh
RUN chmod +x ${REDMINE_INSTALL_DIR}/redmine_ldapsync.sh && \
    chown ${REDMINE_USER}: ${REDMINE_INSTALL_DIR}/redmine_ldapsync.sh

ADD redmine_mailerissues.sh ${REDMINE_INSTALL_DIR}/redmine_mailerissues.sh
RUN chmod +x ${REDMINE_INSTALL_DIR}/redmine_mailerissues.sh && \
    chown ${REDMINE_USER}: ${REDMINE_INSTALL_DIR}/redmine_mailerissues.sh

ADD redmine_githubsync.sh ${REDMINE_INSTALL_DIR}/redmine_githubsync.sh
RUN chmod +x ${REDMINE_INSTALL_DIR}/redmine_githubsync.sh && \
    chown ${REDMINE_USER}: ${REDMINE_INSTALL_DIR}/redmine_githubsync.sh

RUN chown -R redmine /etc/supervisor

USER redmine

ENTRYPOINT ["/usr/local/bin/chaperone"]
CMD []

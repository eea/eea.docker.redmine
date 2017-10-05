FROM redmine:3.4.2
LABEL maintainer="EEA: IDM2 A-Team <eea-edw-a-team-alerts@googlegroups.com>"

ENV REDMINE_PATH=/usr/src/redmine \
    REDMINE_LOCAL_PATH=/var/local/redmine

# Install dependencies and plugins
RUN apt-get update -q \
 && apt-get install -y --no-install-recommends unzip graphviz vim python3-pip \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && pip3 install chaperone \
 && mkdir -p ${REDMINE_LOCAL_PATH}/github /etc/chaperone.d/ \
 && git clone -b RELEASE_0_7_0 https://github.com/tckz/redmine-wiki_graphviz_plugin.git ${REDMINE_PATH}/plugins/wiki_graphviz_plugin \
 && git clone -b Ver_0.3.0 https://github.com/masamitsu-murase/redmine_add_subversion_links.git ${REDMINE_PATH}/plugins/redmine_add_subversion_links \
 && git clone -b v2.2.0 https://github.com/koppen/redmine_github_hook.git ${REDMINE_PATH}/plugins/redmine_github_hook \
 && git clone -b 0.0.2 https://github.com/bluezio/redmine_wiki_backlinks.git ${REDMINE_PATH}/plugins/redmine_wiki_backlinks \
 && git clone -b 0.0.8 https://github.com/bdemirkir/sidebar_hide.git ${REDMINE_PATH}/plugins/sidebar_hide \
 && git clone -b 0.1.2 https://github.com/akiko-pusu/redmine_banner.git ${REDMINE_PATH}/plugins/redmine_banner \
 && git clone https://github.com/Hopebaytech/redmine_mail_reminder.git ${REDMINE_PATH}/plugins/redmine_mail_reminder \
 && cd ${REDMINE_PATH}/plugins/redmine_mail_reminder \
 && git checkout e27585fb3ddb505befcb2614eaeab27755917882 \
 && cd .. \
 && git clone https://github.com/thorin/redmine_ldap_sync.git ${REDMINE_PATH}/plugins/redmine_ldap_sync \
 && cd ${REDMINE_PATH}/plugins/redmine_ldap_sync \
 && git checkout 0ad6646785e58e79264f17a49f7d62f8ca89adcf \
 && cd .. \
 && git clone https://github.com/eea/eea.redmine.theme.git ${REDMINE_PATH}/public/themes/eea.redmine.theme \
 && chown -R redmine:redmine ${REDMINE_PATH} ${REDMINE_LOCAL_PATH}

# Install gems
RUN echo 'gem "dalli", "~> 2.7.6"' >> ${REDMINE_PATH}/Gemfile

# Install eea cron tools
COPY crons/ ${REDMINE_LOCAL_PATH}/crons
COPY config/install_plugins.sh ${REDMINE_PATH}/install_plugins.sh
COPY chaperone.conf /etc/chaperone.d/chaperone.conf

# Send Redmine logs on STDOUT/STDERR
COPY config/additional_environment.rb ${REDMINE_PATH}/config/additional_environment.rb

# Add email configuration
COPY config/configuration.yml ${REDMINE_PATH}/config/configuration.yml

ENTRYPOINT ["/usr/local/bin/chaperone"]
CMD []

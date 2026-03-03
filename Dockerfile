FROM redmine:6.1.1


LABEL maintainer="EEA: IDM2 A-Team <eea-edw-a-team-alerts@googlegroups.com>"

ENV REDMINE_PATH=/usr/src/redmine \
    REDMINE_LOCAL_PATH=/var/local/redmine

# Optional: bake RedmineUP A1 theme into the image.
# Provide A1_THEME_URL at build-time (e.g. via docker-compose build args).
ARG A1_THEME_URL=
ARG A1_THEME_SHA256=

# Install dependencies and plugins
RUN apt-get update -q \
 && apt-get install -y --no-install-recommends build-essential unzip graphviz vim python3-pip cron rsyslog python3-setuptools systemctl \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
  && mkdir -p ${REDMINE_LOCAL_PATH}/github \
  && git clone https://github.com/eea/redmine-wiki_graphviz_plugin.git ${REDMINE_PATH}/plugins/wiki_graphviz_plugin \
  && cd ${REDMINE_PATH}/plugins/wiki_graphviz_plugin \
  && git checkout 33c07e45a6da51637418defa6a640acf8ca745d1 \
  && cd .. \
  && git clone https://github.com/eea/redmine_wiki_backlinks.git ${REDMINE_PATH}/plugins/redmine_wiki_backlinks \
  && cd ${REDMINE_PATH}/plugins/redmine_wiki_backlinks \
  && git checkout be5749d0f258f9a3697342e6ced60af8534ed909 \
  && cd .. \
 && git clone -b 0.3.5 https://github.com/agileware-jp/redmine_banner.git ${REDMINE_PATH}/plugins/redmine_banner \
 && git clone -b 3.4.0 https://github.com/alphanodes/additionals.git ${REDMINE_PATH}/plugins/additionals \
 && git clone -b v1.5.1 https://github.com/mikitex70/redmine_drawio.git ${REDMINE_PATH}/plugins/redmine_drawio \
 && git clone -b 1.0.7 https://github.com/ncoders/redmine_local_avatars.git ${REDMINE_PATH}/plugins/redmine_local_avatars \
  && git clone https://github.com/eea/redmine_xls_export.git ${REDMINE_PATH}/plugins/redmine_xls_export \
  && cd ${REDMINE_PATH}/plugins/redmine_xls_export \
  && git checkout 087afa403b34a32313e7761cd018879f05f19e3c \
  && cd .. \
 && git clone https://github.com/eea/taskman.redmine.theme.git ${REDMINE_PATH}/public/themes/taskman.redmine.theme \
  && git clone -b master https://github.com/eea/redmine_entra_id.git ${REDMINE_PATH}/plugins/entra_id \
  #&& git clone -b 1.11.0 https://github.com/haru/redmine_ai_helper.git ${REDMINE_PATH}/plugins/redmine_ai_helper \
  && if [ -n "$A1_THEME_URL" ]; then \
       THEMES_DIR="${REDMINE_PATH}/public/themes"; \
       if [ -d "${REDMINE_PATH}/themes" ]; then THEMES_DIR="${REDMINE_PATH}/themes"; fi; \
       mkdir -p "$THEMES_DIR"; \
       echo "Downloading A1 theme into $THEMES_DIR"; \
       wget -q -O /tmp/a1-theme.zip "$A1_THEME_URL"; \
       if [ -n "$A1_THEME_SHA256" ]; then echo "$A1_THEME_SHA256  /tmp/a1-theme.zip" | sha256sum -c -; fi; \
       unzip -q -o /tmp/a1-theme.zip -d "$THEMES_DIR"; \
       rm -f /tmp/a1-theme.zip; \
     fi \
  && chown -R redmine:redmine ${REDMINE_PATH} ${REDMINE_LOCAL_PATH} 

# Install gems
RUN echo 'gem "dalli", "~> 2.7.6"' >> ${REDMINE_PATH}/Gemfile \
 && echo 'gem "acts-as-taggable-on", "~> 5.0"' >> ${REDMINE_PATH}/Gemfile 

# Install gems at build-time so image ships complete
RUN /usr/local/bin/bundle install --without development test

# Install eea cron tools
COPY crons/ ${REDMINE_LOCAL_PATH}/crons
COPY config/install_plugins.sh ${REDMINE_PATH}/install_plugins.sh
COPY plugins.cfg ${REDMINE_PATH}/plugins.cfg



COPY redmine_jobs /var/redmine_jobs.txt

RUN sed -i '/#cron./c\cron.*                          \/proc\/1\/fd\/1'  /etc/rsyslog.conf \
 && sed -i '/cron./c\cron.*                          \/proc\/1\/fd\/1'  /etc/rsyslog.conf \
 && sed -i 's/-\/var\/log\/syslog/\/proc\/1\/fd\/1/g'  /etc/rsyslog.conf \
 && systemctl enable rsyslog

RUN echo "export REDMINE_PATH=$REDMINE_PATH\nexport BUNDLE_PATH=$BUNDLE_PATH\nexport BUNDLE_APP_CONFIG=$BUNDLE_PATH\nexport PATH=$BUNDLE_PATH/bin:$PATH"  > ${REDMINE_PATH}/.profile \
 && chown redmine:redmine ${REDMINE_PATH}/.profile \
 && usermod -d ${REDMINE_PATH} redmine

# Send Redmine logs on STDOUT/STDERR
COPY config/additional_environment.rb ${REDMINE_PATH}/config/additional_environment.rb

# Add email configuration
COPY config/configuration.yml ${REDMINE_PATH}/config/configuration.yml

COPY start_redmine.sh /start_redmine.sh
RUN chmod 0766 /start_redmine.sh


ENTRYPOINT ["/start_redmine.sh"]

CMD []

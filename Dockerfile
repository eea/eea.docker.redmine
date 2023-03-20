FROM ruby:2.7-slim-buster

# explicitly set uid/gid to guarantee that it won't change in the future
# the values 999:999 are identical to the current user/group id assigned
RUN groupadd -r -g 999 redmine && useradd -r -g redmine -u 999 redmine

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		wget \
		\
		bzr \
		git \
		mercurial \
		openssh-client \
		subversion \
		\
# we need "gsfonts" for generating PNGs of Gantt charts
# and "ghostscript" for creating PDF thumbnails (in 4.1+)
		ghostscript \
		gsfonts \
		imagemagick \
# grab gosu for easy step-down from root
		gosu \
# grab tini for signal processing and zombie killing
		tini \
	; \
# allow imagemagick to use ghostscript for PDF -> PNG thumbnail conversion (4.1+)
	sed -ri 's/(rights)="none" (pattern="PDF")/\1="read" \2/' /etc/ImageMagick-6/policy.xml; \
	rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV production
WORKDIR /usr/src/redmine

# https://github.com/docker-library/redmine/issues/138#issuecomment-438834176
# (bundler needs this for running as an arbitrary user)
ENV HOME /home/redmine
RUN set -eux; \
	[ ! -d "$HOME" ]; \
	mkdir -p "$HOME"; \
	chown redmine:redmine "$HOME"; \
	chmod 1777 "$HOME"

ENV REDMINE_VERSION 4.2.8
ENV REDMINE_DOWNLOAD_URL https://www.redmine.org/releases/redmine-4.2.8.tar.gz
ENV REDMINE_DOWNLOAD_SHA256 0b431c052d8fd36b93201dafaf3615cdb8d03460efcf2400e7d32662b2ab6272

RUN set -eux; \
# if we use wget here, we get certificate issues (https://github.com/docker-library/redmine/pull/249#issuecomment-984176479)
	curl -fL -o redmine.tar.gz "$REDMINE_DOWNLOAD_URL"; \
	echo "$REDMINE_DOWNLOAD_SHA256 *redmine.tar.gz" | sha256sum -c -; \
	tar -xf redmine.tar.gz --strip-components=1; \
	rm redmine.tar.gz files/delete.me log/delete.me; \
	mkdir -p log public/plugin_assets sqlite tmp/pdf tmp/pids; \
	chown -R redmine:redmine ./; \
# log to STDOUT (https://github.com/docker-library/redmine/issues/108)
	echo 'config.logger = Logger.new(STDOUT)' > config/additional_environment.rb; \
# fix permissions for running as an arbitrary user
	chmod -R ugo=rwX config db sqlite; \
	find log tmp -type d -exec chmod 1777 '{}' +

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		default-libmysqlclient-dev \
		freetds-dev \
		gcc \
		libpq-dev \
		libsqlite3-dev \
		make \
		patch \
		xz-utils \
	; \
	rm -rf /var/lib/apt/lists/*; \
	\
	gosu redmine bundle config --local without 'development test'; \
# https://github.com/redmine/redmine/commit/23dc108e70a0794f444803ac827a690085dcd557
# ("gem puma" already exists in the Gemfile, but under "group :test" and we want it all the time)
	puma="$(grep -E "^[[:space:]]*gem [:'\"]puma['\",[:space:]].*\$" Gemfile)"; \
	{ echo; echo "$puma"; } | sed -re 's/^[[:space:]]+//' >> Gemfile; \
# fill up "database.yml" with bogus entries so the redmine Gemfile will pre-install all database adapter dependencies
# https://github.com/redmine/redmine/blob/e9f9767089a4e3efbd73c35fc55c5c7eb85dd7d3/Gemfile#L50-L79
	echo '# the following entries only exist to force `bundle install` to pre-install all database adapter dependencies -- they can be safely removed/ignored' > ./config/database.yml; \
	for adapter in mysql2 postgresql sqlserver sqlite3; do \
		echo "$adapter:" >> ./config/database.yml; \
		echo "  adapter: $adapter" >> ./config/database.yml; \
	done; \
	gosu redmine bundle install --jobs "$(nproc)"; \
	rm ./config/database.yml; \
# fix permissions for running as an arbitrary user
	chmod -R ugo=rwX Gemfile.lock "$GEM_HOME"; \
	rm -rf ~redmine/.bundle; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
	find /usr/local -type f -executable -exec ldd '{}' ';' \
		| awk '/=>/ { print $(NF-1) }' \
		| sort -u \
		| grep -v '^/usr/local/' \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u \
		| xargs -r apt-mark manual \
	; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false

VOLUME /usr/src/redmine/files

COPY docker-entrypoint.sh /

EXPOSE 3000
CMD ["rails", "server", "-b", "0.0.0.0"]

LABEL maintainer="EEA: IDM2 A-Team <eea-edw-a-team-alerts@googlegroups.com>"

ENV REDMINE_PATH=/usr/src/redmine \
    REDMINE_LOCAL_PATH=/var/local/redmine

# Install dependencies and plugins
RUN apt-get update -q \
 && apt-get install -y --no-install-recommends unzip graphviz vim python3-pip cron rsyslog python3-setuptools \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p ${REDMINE_LOCAL_PATH}/github \
 && git clone -b v0.8.0 https://github.com/tckz/redmine-wiki_graphviz_plugin.git ${REDMINE_PATH}/plugins/wiki_graphviz_plugin \
 && git clone https://github.com/bluezio/redmine_wiki_backlinks.git ${REDMINE_PATH}/plugins/redmine_wiki_backlinks \
 && cd ${REDMINE_PATH}/plugins/redmine_wiki_backlinks \
 && git checkout 62488fa341d21c9b46b27cbb787ee61b46266d0e \
 && cd .. \
 && git clone -b 0.3.4 https://github.com/akiko-pusu/redmine_banner.git ${REDMINE_PATH}/plugins/redmine_banner \
 && git clone -b 3.0.5 https://github.com/alphanodes/additionals.git ${REDMINE_PATH}/plugins/additionals \
 && git clone -b v1.4.4 https://github.com/mikitex70/redmine_drawio.git ${REDMINE_PATH}/plugins/redmine_drawio \
 && git clone -b 1.0.6 https://github.com/ncoders/redmine_local_avatars.git ${REDMINE_PATH}/plugins/redmine_local_avatars \
  && git clone  https://github.com/eea/redmine_ldap_sync.git ${REDMINE_PATH}/plugins/redmine_ldap_sync \
# Disable keycloak integration
# && git clone -b 1.0.5 https://github.com/eea/redmine_openid_connect.git ${REDMINE_PATH}/plugins/redmine_openid_connect \
 && git clone https://github.com/eea/taskman.redmine.theme.git ${REDMINE_PATH}/public/themes/taskman.redmine.theme \
#  To be changed when upgraded to a version greater then redmine_crm-4_3_1-pro
 && git clone https://github.com/two-pack/redmine_xls_export.git ${REDMINE_PATH}/plugins/redmine_xls_export \
 && cd ${REDMINE_PATH}/plugins/redmine_xls_export \
 && git checkout f44cf9f228298615ea1f37749412c52f0c5b0bc9 \
 && cd .. \
#  Plugins we don't use anymore
# && git clone -b Ver_0.3.0 https://github.com/masamitsu-murase/redmine_add_subversion_links.git ${REDMINE_PATH}/plugins/redmine_add_subversion_links \
# && git clone https://github.com/eea/redmine_github_hook.git ${REDMINE_PATH}/plugins/redmine_github_hook \
# && git clone https://github.com/eea/eea.redmine.theme.git ${REDMINE_PATH}/public/themes/eea.redmine.theme \
 && chown -R redmine:redmine ${REDMINE_PATH} ${REDMINE_LOCAL_PATH} 

# Install gems
RUN echo 'gem "dalli", "~> 2.7.6"' >> ${REDMINE_PATH}/Gemfile \
 && echo 'gem "acts-as-taggable-on", "~> 5.0"' >> ${REDMINE_PATH}/Gemfile

# Install eea cron tools
COPY crons/ ${REDMINE_LOCAL_PATH}/crons
COPY config/install_plugins.sh ${REDMINE_PATH}/install_plugins.sh
COPY plugins.cfg ${REDMINE_PATH}/plugins.cfg

# patches for plugins, to be removed when fixed

#wiki linkis "key not found" error
#Remove when fixed - https://github.com/bluezio/redmine_wiki_backlinks/issues/10
COPY patches/wiki_links_controller.rb  ${REDMINE_PATH}/plugins/redmine_wiki_backlinks/app/controllers/wiki_links_controller.rb

COPY redmine_jobs /var/redmine_jobs.txt

RUN sed -i '/#cron./c\cron.*                          \/proc\/1\/fd\/1'  /etc/rsyslog.conf \
 && sed -i 's/-\/var\/log\/syslog/\/proc\/1\/fd\/1/g'  /etc/rsyslog.conf 

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

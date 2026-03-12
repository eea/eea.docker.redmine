# syntax=docker/dockerfile:1.7

ARG REDMINE_BASE=redmine:6.1.1

FROM ${REDMINE_BASE} AS base

LABEL maintainer="EEA: IDM2 A-Team <eea-edw-a-team-alerts@googlegroups.com>"

ENV REDMINE_PATH=/usr/src/redmine \
  REDMINE_LOCAL_PATH=/var/local/redmine \
  RUBY_YJIT_ENABLE=1 \
  FAST_BOOT=1 \
  RUNTIME_PLUGIN_SYNC=0 \
  RUNTIME_THEME_SYNC=0 \
  RUNTIME_BUNDLE_INSTALL=0

# Fail build if upstream base drifts away from Ruby 3.4.x.
RUN ruby -e 'abort("Ruby 3.4.x is required, got #{RUBY_VERSION}") unless RUBY_VERSION.start_with?("3.4.")'

# Optional: bake RedmineUP assets into the image.
ARG PLUGINS_URL=
ARG PLUGINS_USER=
ARG PLUGINS_PASSWORD=
ARG A1_THEME_URL=
ARG A1_THEME_USER=
ARG A1_THEME_PASSWORD=
ARG A1_THEME_SHA256=
ARG A1_THEME_ZIP=a1_theme-4_1_2.zip
ARG REQUIRE_PRO_PLUGINS=0
ARG REQUIRE_A1_THEME=0

COPY plugins.cfg ${REDMINE_PATH}/plugins.cfg
COPY config/install_pro_assets.sh /usr/local/bin/install_pro_assets.sh

# Install dependencies and plugins
RUN apt-get update -q \
  && apt-get install -y --no-install-recommends build-essential unzip graphviz vim python3-pip cron rsyslog python3-setuptools systemctl default-libmysqlclient-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p ${REDMINE_LOCAL_PATH}/github \
  && git clone https://github.com/eea/redmine-wiki_graphviz_plugin.git ${REDMINE_PATH}/plugins/wiki_graphviz_plugin \
  && cd ${REDMINE_PATH}/plugins/wiki_graphviz_plugin \
  && git checkout 33c07e45a6da51637418defa6a640acf8ca745d1 \
  && sed -i "s/^require[[:space:]]*'kconv'$/# Ruby 3.4 removed kconv; use String#encode below instead/" ${REDMINE_PATH}/plugins/wiki_graphviz_plugin/app/helpers/wiki_graphviz_helper.rb \
  && sed -i "s/t = t.toutf8/t = t.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')/" ${REDMINE_PATH}/plugins/wiki_graphviz_plugin/app/helpers/wiki_graphviz_helper.rb \
  && cd .. \
  && git clone https://github.com/eea/redmine_wiki_backlinks.git ${REDMINE_PATH}/plugins/redmine_wiki_backlinks \
  && cd ${REDMINE_PATH}/plugins/redmine_wiki_backlinks \
  && git checkout be5749d0f258f9a3697342e6ced60af8534ed909 \
  && cd .. \
  && git clone -b 0.3.5 https://github.com/agileware-jp/redmine_banner.git ${REDMINE_PATH}/plugins/redmine_banner \
  && git clone -b 3.4.0 https://github.com/alphanodes/additionals.git ${REDMINE_PATH}/plugins/additionals \
  && sed -i "s#require 'additionals/plugin_version'#require_relative 'lib/additionals/plugin_version'#" ${REDMINE_PATH}/plugins/additionals/init.rb \
  && git clone -b v1.5.1 https://github.com/mikitex70/redmine_drawio.git ${REDMINE_PATH}/plugins/redmine_drawio \
  && git clone -b 1.0.7 https://github.com/ncoders/redmine_local_avatars.git ${REDMINE_PATH}/plugins/redmine_local_avatars \
  && git clone https://github.com/eea/redmine_xls_export.git ${REDMINE_PATH}/plugins/redmine_xls_export \
  && cd ${REDMINE_PATH}/plugins/redmine_xls_export \
  && git checkout 087afa403b34a32313e7761cd018879f05f19e3c \
  && cd .. \
  && git clone -b master https://github.com/eea/redmine_entra_id.git ${REDMINE_PATH}/plugins/entra_id \
  && git clone -b 1.11.0 https://github.com/haru/redmine_ai_helper.git ${REDMINE_PATH}/plugins/redmine_ai_helper \
  && chmod 700 /usr/local/bin/install_pro_assets.sh \
  && /usr/local/bin/install_pro_assets.sh

# Make sure plugin gems and mysql adapter gems are resolved at build-time.
RUN echo 'gem "dalli", "~> 2.7.6"' >> ${REDMINE_PATH}/Gemfile \
  && echo 'gem "acts-as-taggable-on", "~> 5.0"' >> ${REDMINE_PATH}/Gemfile \
  && echo 'gem "redmineup"' >> ${REDMINE_PATH}/Gemfile \
  && echo 'gem "redmine_plugin_kit"' >> ${REDMINE_PATH}/Gemfile \
  && echo 'gem "rails_pulse"' >> ${REDMINE_PATH}/Gemfile \
  && echo 'gem "solid_queue"' >> ${REDMINE_PATH}/Gemfile \
  && echo 'gem "vcard"' >> ${REDMINE_PATH}/Gemfile \
  && echo 'gem "wicked_pdf", "~> 1.1.0"' >> ${REDMINE_PATH}/Gemfile \
  && echo 'gem "wkhtmltopdf-binary"' >> ${REDMINE_PATH}/Gemfile \
  && echo 'gem "ostruct"' >> ${REDMINE_PATH}/Gemfile \
  && printf "\ngem 'puma'\n" >> ${REDMINE_PATH}/Gemfile \
  && ruby -e "path='${REDMINE_PATH}/Gemfile'; targets=%w[oauth2 puma redmineup redmine_plugin_kit rails-controller-testing wicked_pdf wkhtmltopdf-binary liquid vcard ostruct rails_pulse solid_queue]; lines=File.readlines(path); keep_last={}; lines.each_with_index { |line, idx| name = line[/^\\s*gem ['\\\"]([^'\\\"]+)['\\\"]/, 1]; keep_last[name] = idx if name && targets.include?(name) }; filtered = lines.each_with_index.filter_map { |line, idx| name = line[/^\\s*gem ['\\\"]([^'\\\"]+)['\\\"]/, 1]; next if name && targets.include?(name) && keep_last[name] != idx; line }; File.write(path, filtered.join)"

RUN chown -R redmine:redmine ${REDMINE_PATH} ${REDMINE_LOCAL_PATH}


FROM base AS gems

# Keep this in its own stage so most app/config edits do not invalidate gem install cache.
RUN --mount=type=cache,target=/usr/local/bundle/cache \
  printf "production:\n  adapter: mysql2\n\ntest:\n  adapter: mysql2\n" > ${REDMINE_PATH}/config/database.yml \
  && \
  /usr/local/bin/bundle config set without 'development test' \
  && /usr/local/bin/bundle config set retry '5' \
  && /usr/local/bin/bundle config set timeout '30' \
  && /usr/local/bin/bundle install --jobs 4 \
  && /usr/local/bin/bundle clean --force \
  && chmod -R go-w /usr/local/bundle


FROM base AS runtime

COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY --from=gems /usr/src/redmine/Gemfile /usr/src/redmine/Gemfile
COPY --from=gems /usr/src/redmine/Gemfile.lock /usr/src/redmine/Gemfile.lock

# Install eea cron tools
COPY crons/ ${REDMINE_LOCAL_PATH}/crons
COPY config/install_plugins.sh ${REDMINE_PATH}/install_plugins.sh
COPY redmine_jobs /var/redmine_jobs.txt

RUN sed -i '/#cron./c\cron.*                          \/proc\/1\/fd\/1' /etc/rsyslog.conf \
  && sed -i '/cron./c\cron.*                          \/proc\/1\/fd\/1' /etc/rsyslog.conf \
  && sed -i 's/-\/var\/log\/syslog/\/proc\/1\/fd\/1/g' /etc/rsyslog.conf \
  && systemctl enable rsyslog

RUN echo "export REDMINE_PATH=$REDMINE_PATH\nexport BUNDLE_PATH=$BUNDLE_PATH\nexport BUNDLE_APP_CONFIG=$BUNDLE_PATH\nexport PATH=$BUNDLE_PATH/bin:$PATH" > ${REDMINE_PATH}/.profile \
  && chown redmine:redmine ${REDMINE_PATH}/.profile \
  && usermod -d ${REDMINE_PATH} redmine

# Send Redmine logs on STDOUT/STDERR
COPY config/additional_environment.rb ${REDMINE_PATH}/config/additional_environment.rb

# Add email configuration
COPY config/configuration.yml ${REDMINE_PATH}/config/configuration.yml
COPY config/rails_pulse.rb ${REDMINE_PATH}/config/initializers/rails_pulse.rb
COPY config/recurring.yml ${REDMINE_PATH}/config/recurring.yml
COPY config/rails_pulse_migrations/20260310221000_expand_rails_pulse_columns.rb ${REDMINE_PATH}/db/migrate/20260310221000_expand_rails_pulse_columns.rb

# Install Rails Pulse into the image: engine route, initializer, and migrations.
RUN set -euo pipefail \
  && cd ${REDMINE_PATH} \
  && ruby -e "require 'fileutils'; spec = Gem::Specification.find_by_name('rails_pulse'); src = File.join(spec.gem_dir, 'db', 'migrate'); dst = File.join('${REDMINE_PATH}', 'db', 'migrate'); Dir.mkdir(dst) unless Dir.exist?(dst); Dir.glob(File.join(src, '*.rb')).sort.each do |path| base = File.basename(path); suffix = base.sub(/^\\d+_/, ''); exists = File.exist?(File.join(dst, base)) || !Dir.glob(File.join(dst, \"*_#{suffix}\")).empty?; FileUtils.cp(path, File.join(dst, base)) unless exists; end" \
  && ruby -e "require 'fileutils'; spec = Gem::Specification.find_by_name('solid_queue'); src = File.join(spec.gem_dir, 'db', 'migrate'); dst = File.join('${REDMINE_PATH}', 'db', 'migrate'); Dir.mkdir(dst) unless Dir.exist?(dst); Dir.glob(File.join(src, '*.rb')).sort.each do |path| base = File.basename(path); suffix = base.sub(/^\\d+_/, ''); exists = File.exist?(File.join(dst, base)) || !Dir.glob(File.join(dst, \"*_#{suffix}\")).empty?; FileUtils.cp(path, File.join(dst, base)) unless exists; end" \
  && ruby -e "require 'fileutils'; spec = Gem::Specification.find_by_name('rails_pulse'); src = File.join(spec.gem_dir, 'db', 'rails_pulse_schema.rb'); dst = File.join('${REDMINE_PATH}', 'db', 'rails_pulse_schema.rb'); FileUtils.cp(src, dst) unless File.exist?(dst)" \
  && ruby -e "routes='${REDMINE_PATH}/config/routes.rb'; mount_line=\"  mount RailsPulse::Engine, at: '/rails_pulse'\\n\"; content=File.read(routes); unless content.include?('RailsPulse::Engine'); updated = content.sub(/\\nend\\s*\\z/, \"\\n#{mount_line}end\\n\"); raise 'Could not locate routes.rb closing end' if updated == content; File.write(routes, updated); end"

COPY start_redmine.sh /start_redmine.sh
RUN chmod 0766 /start_redmine.sh

ENTRYPOINT ["/start_redmine.sh"]
CMD []

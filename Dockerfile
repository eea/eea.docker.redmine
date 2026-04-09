# syntax=docker/dockerfile:1.7

ARG REDMINE_BASE=redmine:6.1.1@sha256:a97aaee22fb7ff9d0ed691e11f5ad01c6e1dceaae63275fd6a96ac30f76aebfa

FROM ${REDMINE_BASE} AS base

LABEL maintainer="EEA: IDM2 A-Team <eea-edw-a-team-alerts@googlegroups.com>"

ENV REDMINE_PATH=/usr/src/redmine \
  REDMINE_LOCAL_PATH=/var/local/redmine \
  BUNDLE_PATH=/usr/local/bundle \
  BUNDLE_APP_CONFIG=/usr/local/bundle \
  BUNDLE_WITHOUT=development:test \
  PATH=/usr/local/bundle/bin:${PATH} \
  RUBY_YJIT_ENABLE=1 \
  FAST_BOOT=1 \
  STARTUP_ASSET_FIXES=0 \
  APPLY_A1_THEME_OVERRIDES_ON_BOOT=0 \
  ASSETS_PRECOMPILE=0 \
  RUNTIME_PLUGIN_SYNC=0 \
  RUNTIME_THEME_SYNC=0

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
ARG EMBED_PRO_ASSETS=0

# Build-time helpers and manifests.
COPY addons.cfg ${REDMINE_PATH}/addons.cfg
RUN awk -F: '$1 == "plugin" && $2 != "" && $4 != "" { print $2 ":" $4 }' "${REDMINE_PATH}/addons.cfg" > "${REDMINE_PATH}/plugins.cfg"
COPY config/lib/ ${REDMINE_PATH}/config/lib/
COPY config/build/install_pro_assets.sh /usr/local/bin/install_pro_assets.sh
COPY config/build/compose_gemfile_from_plugins.rb /usr/local/bin/compose_gemfile_from_plugins.rb
COPY config/build/install_core_plugins.sh /usr/local/bin/install_core_plugins.sh
COPY config/build/install_engine_integrations.rb /usr/local/bin/install_engine_integrations.rb

# Stage 1: OS packages + open-source plugin checkout.
# Inputs: base Redmine image, build plugin installers/manifests, git refs.
# Outputs: OS deps installed, OSS plugins checked out, optional paid assets embedded.
# Why: create a deterministic source tree before dependency resolution.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  apt-get update -q \
  && apt-get install -y --no-install-recommends build-essential unzip graphviz vim python3-pip cron rsyslog python3-setuptools systemctl default-libmysqlclient-dev libyaml-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && chmod 0755 /usr/local/bin/install_core_plugins.sh \
  && /usr/local/bin/install_core_plugins.sh \
  && chmod 700 /usr/local/bin/install_pro_assets.sh \
  && if [ "${EMBED_PRO_ASSETS}" = "1" ]; then \
       /usr/local/bin/install_pro_assets.sh; \
     else \
       echo "Skipping build-time install of paid plugins/themes (EMBED_PRO_ASSETS=${EMBED_PRO_ASSETS}); runtime sync/PVC will provide them"; \
     fi

# Stage 2: compose Gemfile from base+plugins+documented overrides.
# Inputs: Redmine Gemfile, plugin Gemfiles, config/overrides policy.
# Outputs: final deduplicated Gemfile/Gemfile.lock source for bundle stage.
# Why: keep gem policy explicit and avoid ad-hoc Dockerfile gem mutations.
COPY config/overrides/ ${REDMINE_PATH}/config/overrides/
RUN chmod 700 /usr/local/bin/compose_gemfile_from_plugins.rb \
  && ruby /usr/local/bin/compose_gemfile_from_plugins.rb \
  && find ${REDMINE_PATH}/plugins -mindepth 2 -maxdepth 2 -name Gemfile -delete

RUN chown -R redmine:redmine ${REDMINE_PATH} ${REDMINE_LOCAL_PATH}


FROM base AS gems

# Keep this in its own stage so most app/config edits do not invalidate gem install cache.
# Inputs: composed Gemfile from base stage.
# Outputs: fully installed production bundle.
# Why: maximize cache hits and keep runtime boot fast.
RUN --mount=type=cache,target=/usr/local/bundle/cache \
  printf "production:\n  adapter: mysql2\n\ntest:\n  adapter: mysql2\n" > ${REDMINE_PATH}/config/database.yml \
  && \
  gem install bundler:"$(tail -1 ${REDMINE_PATH}/Gemfile.lock | xargs)" \
  && /usr/local/bin/bundle config set path '/usr/local/bundle' \
  && /usr/local/bin/bundle config set --local without 'development test' \
  && /usr/local/bin/bundle config set retry '5' \
  && /usr/local/bin/bundle config set timeout '30' \
  && /usr/local/bin/bundle install --jobs 4 --no-cache \
  && /usr/local/bin/bundle exec ruby -e "require 'mysql2'; puts \"mysql2=#{Mysql2::VERSION}\"" \
  && /usr/local/bin/bundle clean --force \
  && chmod -R go-w /usr/local/bundle


FROM base AS runtime

# Stage 3: runtime wiring + entrypoint.
# Inputs: bundled gems + runtime scripts/config + custom migrations.
# Outputs: runnable image with clear startup/migrate behavior.
# Why: separate runtime concerns from build-time dependency work.
COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY --from=gems /usr/src/redmine/Gemfile /usr/src/redmine/Gemfile
COPY --from=gems /usr/src/redmine/Gemfile.lock /usr/src/redmine/Gemfile.lock

# Install eea cron tools
COPY crons/ ${REDMINE_LOCAL_PATH}/crons
COPY config/runtime/install_plugins.sh ${REDMINE_PATH}/install_plugins.sh
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
COPY config/cable.yml ${REDMINE_PATH}/config/cable.yml
COPY config/queue.yml ${REDMINE_PATH}/config/queue.yml
COPY config/rails_pulse.rb ${REDMINE_PATH}/config/initializers/rails_pulse.rb
COPY config/mission_control_jobs.rb ${REDMINE_PATH}/config/initializers/mission_control_jobs.rb
COPY config/initializers/test_runtime_compat.rb ${REDMINE_PATH}/config/initializers/test_runtime_compat.rb
COPY config/initializers/runtime_compat.rb ${REDMINE_PATH}/config/initializers/runtime_compat.rb
COPY config/recurring.yml ${REDMINE_PATH}/config/recurring.yml
COPY db/migrate/*.rb ${REDMINE_PATH}/db/migrate/
COPY config/runtime/apply_a1_theme_overrides.sh /usr/local/bin/apply_a1_theme_overrides.sh
COPY config/runtime/prepare_addons_assets.sh /usr/local/bin/prepare_addons_assets.sh
COPY config/runtime/sync_addons_bundle.sh /usr/local/bin/sync_addons_bundle.sh
COPY config/runtime/sync_addons_from_dir.sh /usr/local/bin/sync_addons_from_dir.sh
COPY config/runtime/sync_addons_from_share.sh /usr/local/bin/sync_addons_from_share.sh
COPY config/runtime/migration_runner.rb ${REDMINE_PATH}/config/runtime/migration_runner.rb
COPY config/runtime/common.sh /usr/local/bin/common.sh
COPY config/runtime/kconv.rb ${REDMINE_PATH}/lib/kconv.rb

# Add RailsPulse/SolidQueue integration in a dedicated build step.
RUN set -euo pipefail \
  && cd ${REDMINE_PATH} \
  && chmod 0755 /usr/local/bin/install_engine_integrations.rb \
  && /usr/local/bin/bundle exec ruby /usr/local/bin/install_engine_integrations.rb \
  && engine_files="$(find /usr/local/bundle -path "*/rails_pulse-*/lib/rails_pulse/engine.rb" -type f)" \
  && if [ -n "${engine_files}" ]; then \
       echo "${engine_files}" | while IFS= read -r file; do \
         [ -n "${file}" ] || continue; \
         sed -i "s/controller.class.name.start_with?(\"RailsPulse::\")/controller.class.name.to_s.start_with?(\"RailsPulse::\")/" "${file}"; \
       done; \
     else \
       echo "Skipping rails_pulse engine.rb patch (file not found)"; \
     fi

COPY theme_overrides/ ${REDMINE_PATH}/theme_overrides/
RUN set -euo pipefail \
  && chmod 0755 /usr/local/bin/apply_a1_theme_overrides.sh \
  && chmod 0755 /usr/local/bin/prepare_addons_assets.sh \
  && chmod 0755 /usr/local/bin/sync_addons_bundle.sh \
  && chmod 0755 /usr/local/bin/sync_addons_from_dir.sh \
  && chmod 0755 /usr/local/bin/sync_addons_from_share.sh \
  && chmod 0755 /usr/local/bin/common.sh \
  && chmod 0755 ${REDMINE_PATH}/config/runtime/migration_runner.rb \
  && chmod 0755 ${REDMINE_PATH}/config/lib/addons_manifest.rb \
  && /usr/local/bin/apply_a1_theme_overrides.sh \
  && ADDONS_CURRENT_DIR="${REDMINE_PATH}" \
     PLUGINS_DIR="${REDMINE_PATH}/plugins" \
     THEMES_DIR="${REDMINE_PATH}/themes" \
     /usr/local/bin/prepare_addons_assets.sh \
  && install -d ${REDMINE_PATH}/plugins/additionals/assets/images \
  && install -d ${REDMINE_PATH}/plugins/redmine_contacts_helpdesk/assets/images \
  && install -m 0644 ${REDMINE_PATH}/theme_overrides/a1/images/icons.svg ${REDMINE_PATH}/plugins/additionals/assets/images/icons.svg \
  && install -m 0644 ${REDMINE_PATH}/theme_overrides/a1/images/loading.gif ${REDMINE_PATH}/plugins/redmine_contacts_helpdesk/assets/images/loading.gif
COPY start_redmine.sh /start_redmine.sh
RUN chmod 0755 /start_redmine.sh

ENTRYPOINT ["/start_redmine.sh"]
CMD []


FROM runtime AS ci-runtime

# CI-only additions (kept out of production runtime image)
RUN set -euo pipefail \
  && apt-get update -q \
  && apt-get install -y --no-install-recommends python3 \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && for gem_name in ci_reporter_minitest minitest-reporters; do \
       if ! grep -Eq "^[[:space:]]*gem ['\\\"]${gem_name}['\\\"]" /usr/src/redmine/Gemfile; then \
         echo "gem '${gem_name}'" >> /usr/src/redmine/Gemfile; \
       fi; \
     done \
  && gem install bundler:"$(tail -1 ${REDMINE_PATH}/Gemfile.lock | xargs)" \
  && /usr/local/bin/bundle config set path '/usr/local/bundle' \
  && /usr/local/bin/bundle config unset without || true \
  && /usr/local/bin/bundle config set without '' \
  && /usr/local/bin/bundle install --jobs 4 --no-cache

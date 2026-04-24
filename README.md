## EEA Redmine docker setup

Taskman is a web application based on Redmine that facilitates Agile project management for EEA and Eionet software projects. It comes with some plugins and specific Eionet Redmine theme.

### Table of Contents

- [Introduction](#introduction)
  - [Version](#version)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Plugins](#plugins)
- [Themes](#themes)
- [Shell Access](#shell-access)
- [Upgrading](#upgrading)
- [References](#references)

### Introduction

Dockerfile to build a [Redmine](http://www.redmine.org/) container image based on [the official Redmine Docker image](https://hub.docker.com/_/redmine)

#### Version

See (https://hub.docker.com/_/redmine)

### Installation

Pull the image from the docker index. This is the recommended method of installation as it is easier to update image in the future. These builds are performed by the Trusted Build service.

```bash
docker pull eeacms/redmine:latest
```

Alternately you can build the image yourself.

```bash
git clone https://github.com/eea/eea.docker.taskman.git
cd eea.docker.taskman
docker build --tag="$USER/redmine" .
```

### Quick Start

The quickest way to get started is using [Rancher Template](https://github.com/eea/eea.rancher.catalog/tree/master/templates/taskman).

Alternately, you can manually launch the `redmine` container and the supporting database container (MySQL or PostgreSQL), by following this two step guide.

Step 1. Launch a database container

PostgreSQL
```bash
docker run -d --name some-postgres -e POSTGRES_PASSWORD=secret -e POSTGRES_USER=redmine postgres
```

MySQL
```bash
docker run -d --name some-mysql -e MYSQL_ROOT_PASSWORD=secret -e MYSQL_DATABASE=redmine mysql
```

Step 2. Launch the redmine container

PostgreSQL
```bash
docker run -d --name some-redmine --link some-postgres:postgres redmine
```

MySQL
```bash
docker run -d --name some-redmine --link some-mysql:mysql redmine
```

**NOTE**: Please allow a minute or two for the Redmine application to start.

Point your browser to `http://localhost:8080` and login using the default username and password:

* username: **admin**
* password: **admin**

Make sure you visit the `Administration` link and `Load the default configuration` before creating any projects.

You now have the Redmine application up and ready for testing. If you want to use this image in production the please read on.

*The rest of the document will use the docker command line. You can quite simply adapt your configuration into a `docker-compose.yml` file if you wish to do so.*

### Configuration

See (https://hub.docker.com/_/redmine)

### Structure Map

- `config/build/`: build-time scripts and composition
- `config/runtime/`: runtime/startup orchestration
- `config/overrides/`: documented policy overrides
- `db/migrate/`: image-owned migrations
- `docs/architecture/build-runtime-flow.md`: end-to-end sequence and upgrade guard
- `test/docker-compose.base.yml`: canonical local stack definition
- `test/docker-compose.yml`: default wrapper that extends the base stack
- `test/docker-compose.amd64.yml`: thin amd64-only override (platform + amd64-local extras)

### Build Flow (Current)

The Dockerfile is intentionally split into clear stages:

1. `base`: installs OS deps, checks out open-source plugins, composes `Gemfile` from Redmine + plugin Gemfiles + documented overrides.
2. `gems`: runs `bundle install` (cached stage).
3. `runtime`: copies bundled gems and app config/scripts, wires SolidQueue integration, then sets entrypoint.
4. `ci-runtime`: extends `runtime` with CI-only test dependencies for Jenkins.

Addon source-of-truth is `addons.cfg` (`type:name:location:archive`).
Paid plugins/themes are not embedded by default (`EMBED_PRO_ASSETS=0`) and are expected via runtime sync/PVC.
Build target for local/CI compose is selected via `REDMINE_BUILD_TARGET` (`runtime` by default, `ci-runtime` for Jenkins).
For amd64 local runs, compose files are layered:
`docker compose -f test/docker-compose.yml -f test/docker-compose.amd64.yml ...`.

### Local Test Toggle: Ruby4 + Plugins (On/Off)

`test/docker-compose.base.yml` supports a local toggle via env vars:

- `REDMINE_BASE_IMAGE` controls the Docker base image used at build-time.
- `RUBY_REQUIRED_PREFIX` controls the Docker build-time Ruby version guard.
- `MT_NO_PLUGINS` controls plugin loading at runtime (`0` = enabled, `1` = disabled).

Default mode (off):

```bash
docker compose -f test/docker-compose.yml -f test/docker-compose.amd64.yml up -d --build
```

Ruby4 + plugins mode (on):

```bash
REDMINE_BASE_IMAGE=redmine:ruby402-trixie-amd64 RUBY_REQUIRED_PREFIX=4.0. MT_NO_PLUGINS=0 \
docker compose -f test/docker-compose.yml -f test/docker-compose.amd64.yml up -d --build
```

`ostruct` is included through `config/overrides/gem_overrides.rb` and will be applied
automatically by `compose_gemfile_from_plugins.rb` in this mode.

Switch back off:

```bash
REDMINE_BASE_IMAGE=redmine:6.1.2@sha256:e8a05d36d55f022d3709865cc2932cb87e6701a35ca89aeb8e5af5e8a67b31b0 MT_NO_PLUGINS=1 \
docker compose -f test/docker-compose.yml -f test/docker-compose.amd64.yml up -d --build
```

Gem overrides are documented in:

- `config/overrides/gem_overrides.rb`
- `config/overrides/README.md`

Repository layout (high-level):

1. `config/build/`: build-time scripts (plugin checkout, Gemfile composition, engine integration).
2. `config/runtime/`: runtime/startup scripts (addon sync, theme overrides, plugin install helper).
3. `db/migrate/`: custom migrations shipped with this image.
4. `config/overrides/`: documented policy overrides (gems/theme behavior).

### Upgrade-Safe Migrations

For Redmine upgrades (including future 6.3), run the dedicated migrate container with:

- `RUN_DB_MIGRATE=1`
- `RUN_PLUGIN_MIGRATE=auto` (default behavior when DB migration is enabled)

`start_redmine.sh` now retries both:

- `rake db:migrate`
- `rake redmine:plugins:migrate`

on concurrent migration lock errors, reducing rollout race failures.

### Upgrading

To upgrade to newer redmine releases, simply follow this 4 step upgrade procedure.

**Step 1**: Update the docker image.

```bash
docker pull eeacms/redmine
```

**Step 2**: Stop and remove the currently running image

```bash
docker stop some-redmine
docker rm some-redmine
```

**Step 3**: Backup the database in case something goes wrong.

```bash
mysqldump -h <mysql-server-ip> -uredmine -p --add-drop-table redmine > redmine.sql
```

With docker
```bash
docker exec mysql-redmine mysqldump -h localhost --add-drop-table redmine > redmine.sql
```

**Step 4**: Start the image

```bash
docker run --name=redmine -d [OPTIONS] eeacms/redmine
```

**Step 5**: Restore database from before

```bash
docker exec -i mysql-redmine mysql -h localhost redmine < redmine.sql
```
### References
  * http://www.redmine.org/
  * http://www.redmine.org/projects/redmine/wiki/Guide
  * http://www.redmine.org/projects/redmine/wiki/RedmineInstall
  * https://hub.docker.com/_/redmine
  * https://github.com/eea/eea.rancher.catalog/tree/master/templates/taskman
 

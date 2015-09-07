## EEA Redmine docker setup

Taskman is a web application based on Redmine that facilitates Agile project management for EEA and Eionet software projects. It comes with some plugins and specific Eionet redmine theme.

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

Dockerfile to build a [Redmine](http://www.redmine.org/) container image based on [sameersbn/docker-redmine](https://github.com/sameersbn/docker-redmine)

#### Version

See (https://github.com/sameersbn/docker-redmine#version)

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

The quickest way to get started is using [docker-compose](https://docs.docker.com/compose/).

Alternately, you can manually launch the `redmine` container and the supporting `postgresql` container by following this two step guide.

Step 1. Launch a postgresql container

```bash
docker run --name=postgresql-redmine -d \
  --env='DB_NAME=redmine_production' \
  --env='DB_USER=redmine' --env='DB_PASS=password' \
  --volume=/srv/docker/redmine/postgresql:/var/lib/postgresql \
  sameersbn/postgresql:9.4
```

Step 2. Launch the redmine container

```bash
docker run --name=redmine -d \
  --link=postgresql-redmine:postgresql --publish=10083:80 \
  --env='REDMINE_PORT=10083' \
  --volume=/srv/docker/redmine/redmine:/home/redmine/data \
  eeacms/redmine:latest
```

**NOTE**: Please allow a minute or two for the Redmine application to start.

Point your browser to `http://localhost:10083` and login using the default username and password:

* username: **admin**
* password: **admin**

Make sure you visit the `Administration` link and `Load the default configuration` before creating any projects.

You now have the Redmine application up and ready for testing. If you want to use this image in production the please read on.

*The rest of the document will use the docker command line. You can quite simply adapt your configuration into a `docker-compose.yml` file if you wish to do so.*

### Configuration

See (https://github.com/sameersbn/docker-redmine#configuration)

### Plugins

See (https://github.com/sameersbn/docker-redmine#plugins)

### Themes

See (https://github.com/sameersbn/docker-redmine#themes)

### Shell Access

See (https://github.com/sameersbn/docker-redmine#shell-access)

### Upgrading

To upgrade to newer redmine releases, simply follow this 4 step upgrade procedure.

**Step 1**: Update the docker image.

```bash
docker pull eeacms/redmine
```

**Step 2**: Stop and remove the currently running image

```bash
docker stop redmine
docker rm redmine
```

**Step 3**: Backup the database in case something goes wrong.

```bash
mysqldump -h <mysql-server-ip> -uredmine -p --add-drop-table redmine_production > redmine.sql
```

With docker
```bash
docker exec mysql-redmine mysqldump -h localhost --add-drop-table redmine_production > redmine.sql
```

**Step 4**: Start the image

```bash
docker run --name=redmine -d [OPTIONS] eeacms/redmine
```

**Step 5**: Restore database from before

```bash
docker exec -i mysql-redmine mysql -h localhost redmine_production < redmine.sql
```
### References
  * http://www.redmine.org/
  * http://www.redmine.org/projects/redmine/wiki/Guide
  * http://www.redmine.org/projects/redmine/wiki/RedmineInstall

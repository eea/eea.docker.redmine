#!/usr/bin/env python
""" Update EEA repositories
"""
import os
import sys
import json
import urllib2
import logging
import contextlib
from datetime import datetime
from subprocess import Popen, PIPE, STDOUT

class Sync(object):
    """ Usage: redmine.py <loglevel>

    loglevel:
      - info   Log only status messages (default)

      - debug  Log all messages

    """
    def __init__(self,
        folder='.',
        github="https://api.github.com/orgs/eea/repos?per_page=100&page=%s",
        redmine='http://taskman.eionet.europa.eu/projects/zope/repository',
        timeout=15,
        loglevel=logging.INFO):

        self.folder = folder
        self.github = github
        self.redmine = redmine
        self.timeout = timeout
        self.repos = []

        self.loglevel = loglevel
        self._logger = None

    @property
    def logger(self):
        """ Logger
        """
        if self._logger:
            return self._logger

        # Setup logger
        self._logger = logging.getLogger('redmine')
        self._logger.setLevel(self.loglevel)
        fh = logging.FileHandler('redmine.log')
        fh.setLevel(logging.INFO)
        ch = logging.StreamHandler()
        ch.setLevel(logging.DEBUG)
        formatter = logging.Formatter(
            '%(asctime)s - %(lineno)3d - %(levelname)7s - %(message)s')
        fh.setFormatter(formatter)
        ch.setFormatter(formatter)
        self._logger.addHandler(fh)
        self._logger.addHandler(ch)
        return self._logger

    def refresh_repo(self, name=''):
        """ Refresh redmine repositories
        """
        name = name.replace('.git', '').replace('.', '-')
        name = '/'.join((self.redmine, name))

        self.logger.info('Refreshing repo: %s', name)

        try:
            with contextlib.closing(
                urllib2.urlopen(name, timeout=self.timeout)) as conn:
                self.logger.debug(conn.read())
        except urllib2.HTTPError, err:
            self.logger.warn(err)
        except Exception, err:
            self.logger.exception(err)

    def update_repo(self, name):
        """ Update repo
        """
        self.logger.info('Updating repo: %s', name)
        cmd = 'cd %(name)s && git fetch --all' % {'name': name}
        process = Popen(cmd, shell=True,
                        stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True)
        res = process.stdout.read()
        self.logger.debug(res)

        self.refresh_repo(name)

    def sync_repo(self, repo):
        """ Sync repo
        """
        existing = os.listdir('.')

        name = repo.get('name', '') + '.git'
        self.logger.info('Syncing repo: %s', name)

        if name in existing:
            return self.update_repo(name)

        cmd = 'git clone --mirror %(url)s' % {'url': repo.get('clone_url', '')}

        process = Popen(cmd, shell=True,
                        stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True)
        res = process.stdout.read()
        self.logger.debug(res)
        return self.update_repo(name)

    def sync_repos(self):
        """ Sync all repos
        """
        count = len(self.repos)
        self.logger.info('Syncing %s repositories', count)
        start = datetime.now()
        for repo in self.repos:
            self.sync_repo(repo)
        # Refresh default redmine repository
        self.refresh_repo()

        end = datetime.now()
        self.logger.info('DONE Syncing %s repositories in %s seconds',
                         count, (end - start).seconds)

    def start(self):
        """ Start syncing
        """
        self.repos = []
        links = [self.github % count for count in range(1,100)]
        try:
            for link in links:
                with contextlib.closing(
                    urllib2.urlopen(link, timeout=self.timeout)) as conn:
                    repos = json.loads(conn.read())
                    if not repos:
                        break
                    self.logger.info('Adding repositories from %s',  link)
                    self.repos.extend(repos)
            self.sync_repos()
        except Exception, err:
            self.logger.exception(err)

    __call__ = start

if __name__ == "__main__":
    LOG = len(sys.argv) > 1 and sys.argv[1] or 'info'
    if LOG not in ('debug', 'info'):
        print Sync.__doc__
        sys.exit(1)

    if LOG.lower() == 'info':
        LOGLEVEL = logging.INFO
    else:
        LOGLEVEL = logging.DEBUG

    sync = Sync(loglevel=LOGLEVEL)
    sync.start()

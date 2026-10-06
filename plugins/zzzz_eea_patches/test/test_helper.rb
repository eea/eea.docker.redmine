ENV["RAILS_ENV"] = 'test'
# Use Redmine's fixture setup, transactional tests, Mocha and cache cleanup.
require File.expand_path('../../../test/test_helper', __dir__)
require 'benchmark'

# frozen_string_literal: true

# Standalone check of the Ruby autoload contract used by Zeitwerk.
require 'minitest/autorun'
require 'open3'
require 'rbconfig'

class PluginLoadingTest < Minitest::Test
  LIB_PATH = File.expand_path('../../lib', __dir__)
  BOOT_CHECK = <<~'RUBY'
    module Rails
      class Configuration
        attr_reader :callbacks
        def initialize
          @callbacks = []
        end
        def to_prepare(&block)
          callbacks << block
        end
      end
      def self.application
        @application ||= Struct.new(:config).new(Configuration.new)
      end
    end
    module Redmine
      module Hook
        class ViewListener; end
      end
      module Plugin
        def self.installed?(_name); false; end
      end
      module Helpers
        class Gantt; end
      end
    end
    class Issue; end
    class Tracker
      def self.reflect_on_association(_name); nil; end
    end
    def require_dependency(_name); end

    lib = ARGV.fetch(0)
    # Check both plugin-init requires before autoload registration and autoload
    # registration before any plugin library has been required.
    if ARGV.fetch(1) == 'require_first'
      require File.join(lib, 'issue_tracker_color_patch')
    end
    expected = []
    register = lambda do |directory, namespace|
      Dir.children(directory).sort.each do |entry|
        path = File.join(directory, entry)
        name = entry.delete_suffix('.rb').split('_').map(&:capitalize).join
        if File.directory?(path)
          namespace.const_set(name, Module.new) unless namespace.const_defined?(name, false)
          register.call(path, namespace.const_get(name, false))
        elsif entry.end_with?('.rb')
          namespace.autoload(name, path) unless namespace.const_defined?(name, false)
          expected << [namespace, name]
        end
      end
    end
    register.call(lib, Object)
    expected.each { |namespace, name| namespace.const_get(name, false) }
    raise 'Missing prepare callback' unless Rails.application.config.callbacks.size == 1
    2.times { Rails.application.config.callbacks.each(&:call) }
    raise 'Issue patch duplicated' unless Issue.ancestors.count(EeaPatches::TrackerColorPatches::IssueColors) == 1
    raise 'Gantt patch duplicated' unless Redmine::Helpers::Gantt.ancestors.count(EeaPatches::TrackerColorPatches::GanttColors) == 1
    puts 'Plugin constants and prepare callbacks loaded successfully'
  RUBY

  def test_autoload_before_plugin_requires
    check_loading('autoload_first')
  end

  def test_plugin_requires_before_autoload
    check_loading('require_first')
  end

  private

  def check_loading(order)
    output, status = Open3.capture2e(RbConfig.ruby, '-e', BOOT_CHECK, LIB_PATH, order)
    assert status.success?, output
    assert_includes output, 'Plugin constants and prepare callbacks loaded successfully'
  end
end

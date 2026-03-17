#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'rubygems'

redmine_path = ENV.fetch('REDMINE_PATH', '/usr/src/redmine')
migrate_dir = File.join(redmine_path, 'db', 'migrate')
routes_path = File.join(redmine_path, 'config', 'routes.rb')

def copy_engine_migrations(gem_name, migrate_dir)
  spec = Gem::Specification.find_by_name(gem_name)
  src = File.join(spec.gem_dir, 'db', 'migrate')
  Dir.mkdir(migrate_dir) unless Dir.exist?(migrate_dir)
  Dir.glob(File.join(src, '*.rb')).sort.each do |path|
    base = File.basename(path)
    suffix = base.sub(/^\d+_/, '')
    exists = File.exist?(File.join(migrate_dir, base)) || !Dir.glob(File.join(migrate_dir, "*_#{suffix}")).empty?
    FileUtils.cp(path, File.join(migrate_dir, base)) unless exists
  end
end

copy_engine_migrations('rails_pulse', migrate_dir)
copy_engine_migrations('solid_queue', migrate_dir)

rails_pulse_schema_src = File.join(Gem::Specification.find_by_name('rails_pulse').gem_dir, 'db',
                                   'rails_pulse_schema.rb')
rails_pulse_schema_dst = File.join(redmine_path, 'db', 'rails_pulse_schema.rb')
FileUtils.cp(rails_pulse_schema_src, rails_pulse_schema_dst) unless File.exist?(rails_pulse_schema_dst)

routes = File.read(routes_path)
mounts = []
mounts << "  mount RailsPulse::Engine, at: '/rails_pulse'\n" unless routes.include?('RailsPulse::Engine')
mounts << "  mount MissionControl::Jobs::Engine, at: '/jobs'\n" unless routes.include?('MissionControl::Jobs::Engine')

unless mounts.empty?
  updated = routes.sub(/\nend\s*\z/, "\n#{mounts.join}end\n")
  raise 'Could not locate routes.rb closing end' if updated == routes

  File.write(routes_path, updated)
end

puts 'Engine integrations prepared (rails_pulse, solid_queue, routes).'

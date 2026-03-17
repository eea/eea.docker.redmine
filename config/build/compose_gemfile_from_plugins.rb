#!/usr/bin/env ruby
# frozen_string_literal: true

redmine_path = ENV.fetch("REDMINE_PATH", "/usr/src/redmine")
gemfile_path = File.join(redmine_path, "Gemfile")
plugins_dir = File.join(redmine_path, "plugins")
overrides_path = File.join(redmine_path, "config", "overrides", "gem_overrides.rb")

begin_marker = "# BEGIN managed addon gems"
end_marker = "# END managed addon gems"

gem_decl = /^\s*gem\s+['"]([^'"]+)['"]/

unless File.exist?(gemfile_path)
  warn "Gemfile not found: #{gemfile_path}"
  exit 1
end

base_lines = File.readlines(gemfile_path, chomp: true)

# Remove previously managed block if present.
start_idx = base_lines.index { |line| line.include?(begin_marker) }
end_idx = base_lines.index { |line| line.include?(end_marker) }
if start_idx && end_idx && end_idx > start_idx
  base_lines.slice!(start_idx..end_idx)
  base_lines.pop while base_lines.last&.empty?
end

plugin_entries = []
Dir.glob(File.join(plugins_dir, "*", "Gemfile")).sort.each do |plugin_gemfile|
  File.readlines(plugin_gemfile, chomp: true).each do |line|
    next unless line.match?(gem_decl)

    plugin_entries << line
  end
end

override_entries = []
if File.exist?(overrides_path)
  File.readlines(overrides_path, chomp: true).each do |line|
    next unless line.match?(gem_decl)

    override_entries << line
  end
end

managed_block = []
managed_block << ""
managed_block << begin_marker
managed_block << "# from plugin Gemfiles in /plugins/*/Gemfile"
plugin_entries.each { |gem_line| managed_block << gem_line }
managed_block << "# from config/overrides/gem_overrides.rb (documented overrides)"
override_entries.each { |line| managed_block << line }
managed_block << end_marker

combined = base_lines + managed_block

# Deduplicate gem declarations globally by gem name (keep last declaration).
last_index = {}
combined.each_with_index do |line, idx|
  name = line[gem_decl, 1]
  last_index[name] = idx if name
end

deduped = []
combined.each_with_index do |line, idx|
  name = line[gem_decl, 1]
  next if name && last_index[name] != idx

  deduped << line
end

File.write(gemfile_path, deduped.join("\n") + "\n")
puts "Composed Gemfile from plugins and overrides: #{gemfile_path}"

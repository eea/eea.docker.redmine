#!/usr/bin/env ruby
# frozen_string_literal: true

module AddonsManifest
  Entry = Struct.new(:type, :name, :location, :archive, keyword_init: true)

  module_function

  def path
    ENV.fetch("ADDONS_CFG", File.join(ENV.fetch("REDMINE_PATH", "/usr/src/redmine"), "addons.cfg"))
  end

  def read_entries
    raise "addons.cfg not found: #{path}" unless File.exist?(path)

    entries = []
    File.readlines(path, chomp: true).each do |line|
      next if line.strip.empty? || line.lstrip.start_with?("#")

      type, name, location, archive = line.split(":", 4)
      next if [type, name, location, archive].any? { |v| v.nil? || v.empty? }

      entries << Entry.new(type: type, name: name, location: location, archive: archive)
    end
    entries
  end

  def plugins
    read_entries.select { |entry| entry.type == "plugin" }
  end

  def themes
    read_entries.select { |entry| entry.type == "theme" }
  end

  def theme_entry(theme_id = ENV.fetch("A1_THEME_ID", "a1"))
    themes.find { |entry| entry.name == theme_id } || themes.first
  end

  def dump_entries(entries)
    entries.each { |e| puts "#{e.type}:#{e.name}:#{e.location}:#{e.archive}" }
  end
end

cmd = ARGV.shift

begin
  case cmd
  when "validate"
    AddonsManifest.read_entries
    puts "ok"
  when "list"
    AddonsManifest.dump_entries(AddonsManifest.read_entries)
  when "plugins"
    AddonsManifest.dump_entries(AddonsManifest.plugins)
  when "theme-archive"
    entry = AddonsManifest.theme_entry
    puts(entry&.archive || "")
  when "theme-location"
    entry = AddonsManifest.theme_entry
    puts(entry&.location || "")
  when "has-plugin-archive"
    archive = ARGV.shift.to_s
    found = AddonsManifest.plugins.any? { |entry| entry.archive == archive }
    puts(found ? "1" : "0")
  when "json"
    payload = AddonsManifest.read_entries.map(&:to_h)
    body = payload.map do |h|
      "{\"type\":\"#{h[:type]}\",\"name\":\"#{h[:name]}\",\"location\":\"#{h[:location]}\",\"archive\":\"#{h[:archive]}\"}"
    end.join(",")
    puts "[#{body}]"
  else
    warn "usage: #{File.basename(__FILE__)} [validate|list|plugins|theme-archive|theme-location|has-plugin-archive <archive>|json]"
    exit 1
  end
rescue StandardError => e
  warn e.message
  exit 1
end

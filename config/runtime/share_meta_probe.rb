#!/usr/bin/env ruby
# Probe the addons share for per-archive metadata using WebDAV PROPFIND.
#
# Reads the pinned addon list from addons.cfg, issues ONE PROPFIND (Depth: 1)
# per distinct location (e.g. plugins/, themes/) over a single TLS connection,
# and prints one TSV row per pinned archive, in addons.cfg order:
#
#   <location>\t<archive>\t<etag>\t<size>\t<mtime>
#
# The etag is content-derived by Nextcloud (32-hex md5 for files), so it is a
# true content fingerprint; size/mtime are bonus sanity fields.
#
# Env:
#   ADDONS_BASE_URL   share root (preferred) or
#   PLUGINS_URL       .../redmine6-files/plugins (trailing /plugins stripped)
#   PLUGINS_USER / PLUGINS_PASSWORD
#   ADDONS_CFG        default /usr/src/redmine/addons.cfg
#
# Exit codes:
#   0  all pinned archives found
#   1  network/auth failure after retries
#   2  one or more pinned archives missing from the share

require 'net/http'
require 'uri'
require 'base64'

CFG = ENV.fetch('ADDONS_CFG', '/usr/src/redmine/addons.cfg')
USER = ENV['PLUGINS_USER']
PASS = ENV['PLUGINS_PASSWORD']
BASE = ENV['ADDONS_BASE_URL'] ||
  (ENV['PLUGINS_URL'] && ENV['PLUGINS_URL'].sub(%r{/plugins\z}, ''))
CONNECT_TIMEOUT = 5
READ_TIMEOUT = 20
ATTEMPTS = 2

abort 'PLUGINS_USER/PLUGINS_PASSWORD required' unless USER && PASS
abort 'ADDONS_BASE_URL or PLUGINS_URL required' unless BASE && !BASE.empty?
abort "addons cfg not found: #{CFG}" unless File.file?(CFG)

pinned = File.readlines(CFG).filter_map do |line|
  line = line.strip
  next if line.empty? || line.start_with?('#')
  kind, name, location, archive = line.split(':')
  next unless kind && name && location && archive
  next unless %w[plugin theme].include?(kind)
  [kind, name, location, archive]
end
abort 'no pinned addons found in cfg' if pinned.empty?

base_uri = URI.parse(BASE)
auth = 'Basic ' + Base64.strict_encode64("#{USER}:#{PASS}")

def make_http(base_uri, connect_timeout, read_timeout)
  http = Net::HTTP.new(base_uri.host, base_uri.port)
  http.use_ssl = (base_uri.scheme == 'https')
  http.open_timeout = connect_timeout
  http.read_timeout = read_timeout
  http
end

def propfind_files(http, path, auth)
  body = '<d:propfind xmlns:d="DAV:"><d:prop><d:getetag/><d:getlastmodified/><d:getcontentlength/></d:prop></d:propfind>'
  req = Net::HTTPGenericRequest.new('PROPFIND', true, body, path)
  req['Authorization'] = auth
  req['Depth'] = '1'
  req['Content-Type'] = 'application/xml'
  resp = http.request(req)
  raise "PROPFIND #{path} -> HTTP #{resp.code}" unless resp.code == '207'

  resp.body.to_s.scan(/<d:response>.*?<\/d:response>/m).each_with_object({}) do |block, acc|
    href = block[/<d:href>([^<]+)<\/d:href>/, 1]
    next unless href
    next if block.include?('<d:collection/>')
    name = URI.decode_www_form_component(href.split('/').last)
    etag = block[/<d:getetag>\s*(?:&quot;|")?([^"<&]+)(?:&quot;|")?\s*<\/d:getetag>/, 1]
    size = block[/<d:getcontentlength>(\d+)<\/d:getcontentlength>/, 1]
    mtime = block[/<d:getlastmodified>([^<]+)<\/d:getlastmodified>/, 1]
    acc[name] = [etag.to_s, size.to_s, mtime.to_s]
  end
end

        http = make_http(base_uri, CONNECT_TIMEOUT, READ_TIMEOUT)
by_location = pinned.group_by { |entry| entry[2] }
meta_by_location = {}
failures = []

by_location.each do |location, _entries|
  path = "#{base_uri.path}/#{location}"
  ATTEMPTS.times do |attempt|
    begin
      meta_by_location[location] = propfind_files(http, path, auth)
      break
    rescue StandardError => e
      meta_by_location[location] = nil
      if attempt + 1 < ATTEMPTS
        begin
          http.finish
        rescue StandardError
          nil
        end
http = make_http(base_uri, CONNECT_TIMEOUT, READ_TIMEOUT)
        sleep 2
      else
        failures << "#{path}: #{e.class}: #{e.message}"
      end
    end
  end
end

missing = []
pinned.each do |_kind, _name, location, archive|
  meta = (meta_by_location[location] || {})[archive]
  if meta
    puts "#{location}\t#{archive}\t#{meta[0]}\t#{meta[1]}\t#{meta[2]}"
  else
    warn "pinned archive not found in share: #{location}/#{archive}"
    missing << "#{location}/#{archive}"
  end
end

begin
  http.finish
rescue StandardError
  nil
end

failures.each { |f| warn f }
exit(1) unless failures.empty?
exit(2) unless missing.empty?
exit(0)

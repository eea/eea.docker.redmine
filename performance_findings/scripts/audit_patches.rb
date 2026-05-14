# frozen_string_literal: true

require 'set'
require 'yaml'

ROOT = File.expand_path('../..', __dir__)
RUNTIME = File.join(ROOT, 'config/initializers/runtime_compat.rb')
STALE = File.join(ROOT, 'config/stale/runtime_compat_disabled_patches.rb')
VALUES_LOCAL = File.join(ROOT, 'helm/values.local.yaml')
TEST_COMPOSE = File.join(ROOT, 'test/docker-compose.base.yml')
ALLOWLIST = File.join(__dir__, 'audit_patches_allowlist.yml')

def extract_toggles(file)
  return Set.new unless File.exist?(file)
  content = File.read(file)
  Set.new(content.scan(/patch_enabled\?\('([A-Z0-9_]+)'\)/).flatten)
end

def extract_env_keys(file)
  return Set.new unless File.exist?(file)
  content = File.read(file)
  Set.new(content.scan(/TASKMAN_PATCH_([A-Z0-9_]+)/).flatten)
end

runtime_toggles = extract_toggles(RUNTIME)
stale_toggles = extract_toggles(STALE)

allow_cfg = File.exist?(ALLOWLIST) ? YAML.load_file(ALLOWLIST) : {}
allow_undeclared = Set.new(Array(allow_cfg['intentionally_undeclared']).map(&:to_s))

declared_in_values = extract_env_keys(VALUES_LOCAL)
declared_in_compose = extract_env_keys(TEST_COMPOSE)
declared_anywhere = declared_in_values | declared_in_compose

missing_declaration = runtime_toggles - declared_anywhere
missing_declaration_unexpected = missing_declaration - allow_undeclared
missing_declaration_allowlisted = missing_declaration & allow_undeclared
orphaned_declaration = declared_anywhere - runtime_toggles
stale_reference_declaration = stale_toggles & declared_anywhere

puts 'Patch Toggle Audit'
puts '=' * 80
puts "Runtime toggles (active): #{runtime_toggles.size}"
puts "Stale toggles (archived): #{stale_toggles.size}"
puts "Declared toggles (values+compose): #{declared_anywhere.size}"
puts

puts 'Category: MISSING_DECLARATION'
if missing_declaration_unexpected.empty?
  puts '  none'
else
  missing_declaration_unexpected.sort.each { |t| puts "  - TASKMAN_PATCH_#{t}" }
end
puts

puts 'Category: MISSING_DECLARATION_ALLOWLISTED'
if missing_declaration_allowlisted.empty?
  puts '  none'
else
  missing_declaration_allowlisted.sort.each { |t| puts "  - TASKMAN_PATCH_#{t}" }
end
puts

puts 'Category: ORPHANED_DECLARATION'
if orphaned_declaration.empty?
  puts '  none'
else
  orphaned_declaration.sort.each { |t| puts "  - TASKMAN_PATCH_#{t}" }
end
puts

puts 'Category: STALE_REFERENCE_DECLARATION'
if stale_reference_declaration.empty?
  puts '  none'
else
  stale_reference_declaration.sort.each { |t| puts "  - TASKMAN_PATCH_#{t}" }
end
puts

exit_code = (missing_declaration_unexpected.any? || stale_reference_declaration.any?) ? 2 : 0
puts "Audit result: #{exit_code.zero? ? 'OK' : 'DRIFT_FOUND'}"
exit exit_code

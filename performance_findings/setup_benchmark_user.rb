# frozen_string_literal: true

# Usage:
#   RAILS_ENV=production bundle exec rails runner performance_findings/setup_benchmark_user.rb

BENCH_LOGIN = ENV.fetch('BENCH_LOGIN', 'perfbench')
BENCH_PASSWORD = ENV.fetch('BENCH_PASSWORD', 'PerfBench!123456')
BENCH_PROJECT_IDENTIFIER = ENV.fetch('BENCH_PROJECT_IDENTIFIER', 'perf_intensive_test')

project = Project.find_by(identifier: BENCH_PROJECT_IDENTIFIER)
raise "Project '#{BENCH_PROJECT_IDENTIFIER}' not found" unless project

user = User.find_or_initialize_by(login: BENCH_LOGIN)
if user.new_record?
  user.firstname = 'Perf'
  user.lastname = 'Benchmark'
  user.mail = "#{BENCH_LOGIN}@example.invalid"
  user.language = Setting.default_language.presence || 'en'
  user.status = User::STATUS_ACTIVE
end

user.password = BENCH_PASSWORD
user.password_confirmation = BENCH_PASSWORD
user.must_change_passwd = false if user.respond_to?(:must_change_passwd=)
user.admin = false
user.save!

role = Role.where(builtin: 0).where.not(permissions: nil).first || Role.first
raise 'No Role found to grant project membership' unless role

member = Member.find_by(project_id: project.id, user_id: user.id)
if member.nil?
  # Create member with role attached atomically (required by this setup).
  member = Member.new(project_id: project.id, user_id: user.id)
  member.member_roles.build(role_id: role.id)
  member.save!
elsif !member.member_roles.where(role_id: role.id).exists?
  member.member_roles.create!(role_id: role.id)
end

puts "BENCH_USER_LOGIN=#{BENCH_LOGIN}"
puts "BENCH_USER_PASSWORD=#{BENCH_PASSWORD}"
puts "BENCH_USER_ID=#{user.id}"
puts "BENCH_PROJECT_ID=#{project.id}"
puts "BENCH_ROLE_ID=#{role.id}"

# frozen_string_literal: true

# db/seeds/members_perf_test.rb
# Creates 60,000 members for performance testing
# Run with: rails runner db/seeds/members_perf_test.rb

require '/usr/src/redmine/config/environment'

puts "Creating member performance test data..."

test_project = Project.find_or_create_by!(identifier: 'members-perf-test') do |p|
  p.name = "Members Performance Test"
  p.is_public = false
end

roles = Role.where.not(name: 'Anonymous').to_a
users = User.active.where(type: 'User').to_a

puts "Using #{users.size} users and #{roles.size} roles"
puts "Creating 60,000 members..."

Member.where(project_id: test_project.id).delete_all
MemberRole.delete_all

member_count = 60_000
now = Time.now

member_records = []
member_count.times do |i|
  # Rotate through users to avoid duplicate key constraint
  user_idx = i % users.size
  # Also rotate through projects to distribute members
  project_idx = (i / users.size) % 5
  project = project_idx == 0 ? test_project : Project.offset(rand(Project.count)).first

  member_records << {
    project_id: project.id,
    user_id: users[user_idx].id,
    created_on: now,
    mail_notification: 0
  }

  if member_records.size >= 1000
    Member.insert_all!(member_records) rescue nil
    puts "  Inserted #{i + 1}/#{member_count}..."
    member_records = []
  end
end

if member_records.any?
  Member.insert_all!(member_records) rescue nil
end

puts "Members inserted: #{Member.where(project_id: test_project.id).count}"

member_role_records = []
Member.where(project_id: test_project.id).find_each.with_index do |member, i|
  member_role_records << {
    member_id: member.id,
    role_id: roles[i % roles.size].id
  }

  if member_role_records.size >= 1000
    MemberRole.insert_all!(member_role_records)
    member_role_records = []
  end
end

if member_role_records.any?
  MemberRole.insert_all!(member_role_records)
end

puts "Member roles inserted: #{MemberRole.count}"
puts ""
puts "Test project: /projects/#{test_project.identifier}"
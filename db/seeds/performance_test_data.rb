# frozen_string_literal: true

# db/seeds/performance_test_data.rb
#
# Seed data for benchmarking plugin query optimizations
# Run with: rails runner db/seeds/performance_test_data.rb
#
# This seed creates data that exercises the indexes added for optimization:
# - issues.project_id
# - helpdesk_tickets.issue_id
# - contacts.id
# - projects.parent_id
# - issues.status_id
# - issues.assigned_to_id
# - issues.tracker_id

puts "Creating performance test data..."

# Ensure we have base data
unless Project.any?
  puts "ERROR: No projects found. Please run standard Redmine seeds first."
  exit 1
end

# Helper to safely check if a class exists
def class_exists?(klass_name)
  klass_name.constantize rescue nil
end

# ============================================================================
# PROJECTS WITH SUBPROJECTS (Test project hierarchy + parent_id index)
# ============================================================================
puts "Creating projects with subprojects..."

projects = []
5.times do |i|
  parent = Project.find_or_create_by!(
    name: "Perf Test Parent #{i + 1}",
    identifier: "perf_parent_#{i + 1}"
  ) do |p|
    p.description = "Performance test parent project #{i + 1}"
    p.is_public = false
  end
  projects << parent

  2.times do |j|
    child = Project.find_or_create_by!(
      name: "Perf Test Sub #{i + 1}-#{j + 1}",
      identifier: "perf_sub_#{i + 1}_#{j + 1}"
    ) do |p|
      p.parent = parent
      p.description = "Performance test subproject #{i + 1}-#{j + 1}"
      p.is_public = false
    end
    projects << child
  end
end

puts "  Created #{projects.size} projects (5 parents + 10 children)"

# ============================================================================
# ISSUES WITH VARIOUS STATUSES, TRACKERS, ASSIGNEES
# (Test issues.project_id, issues.status_id, issues.assigned_to_id, issues.tracker_id indexes)
# ============================================================================
puts "Creating issues..."

statuses = IssueStatus.all.to_a
trackers = Tracker.all.to_a
priorities = IssuePriority.all.to_a
users = User.active.all.to_a

raise "ERROR: No issue statuses found. Run Redmine seeds first." if statuses.empty?
raise "ERROR: No trackers found. Run Redmine seeds first." if trackers.empty?
raise "ERROR: No active users found. Run Redmine seeds first." if users.empty?

# Create 50 issues across projects
issue_count = 0
projects.each do |project|
  next if project.parent.nil? # Only create issues on leaf projects

  5.times do |i|
    issue = Issue.find_or_create_by!(
      project: project,
      subject: "Perf Test Issue #{project.identifier}-#{i + 1}",
      tracker: trackers.sample,
      status: statuses.sample,
      priority: priorities.sample,
      assigned_to: users.sample
    ) do |t|
      t.author = users.sample
      t.description = "Performance test issue for benchmarking query optimizations"
    end
    issue_count += 1
  end
end

puts "  Created #{issue_count} issues across #{projects.select { |p| p.parent }.size} subprojects"

# ============================================================================
# HELPDEK TICKETS LINKED TO ISSUES
# (Test helpdesk_tickets.issue_id index + joins optimization)
# ============================================================================
puts "Creating helpdesk tickets..."

helpdesk_klass = class_exists?('HelpdeskTicket')
if helpdesk_klass && helpdesk_klass.table_exists?
  contact_klass = class_exists?('Contact')

  issues_with_issues = Issue.where(project_id: projects.map(&:id)).limit(30).to_a

  tickets_created = 0
  issues_with_issues.each do |issue|
    next if helpdesk_klass.joins(:issue).where(issues: { id: issue.id }).exists?

    ticket_attributes = {
      issue_id: issue.id,
      source: 0, # email
      from_address: "perf_test_#{tickets_created}@example.com",
      to_address: "support@eea.europa.eu",
      ticket_date: Time.now
    }

    # Link to contact if available
    if contact_klass && contact_klass.table_exists?
      contact = contact_klass.first
      ticket_attributes[:contact_id] = contact.id if contact
    end

    helpdesk_klass.create!(ticket_attributes) rescue nil
    tickets_created += 1
  end

  puts "  Created #{tickets_created} helpdesk tickets"
else
  puts "  SKIPPED: HelpdeskTicket class not available"
end

# ============================================================================
# DEALS WITH DIFFERENT STATUSES AND CURRENCIES
# (Test deals + CRM optimizations)
# ============================================================================
puts "Creating deals..."

deal_klass = class_exists?('Deal')
if deal_klass && deal_klass.table_exists?
  contact_klass = class_exists?('Contact')

  deal_statuses = deal_klass.respond_to?(:statuses) ? deal_klass.statuses : %w[open won lost]
  currencies = %w[EUR USD GBP]

  10.times do |i|
    contact = nil
    if contact_klass && contact_klass.table_exists?
      contact = contact_klass.offset(rand(contact_klass.count)).first
    end

    deal_klass.find_or_create_by!(
      name: "Perf Test Deal #{i + 1}",
      project_id: projects.sample.id
    ) do |d|
      d.contact_id = contact.id if contact
      d.status = deal_statuses.sample
      d.amount = rand(1000..100000)
      d.currency = currencies.sample
      d.estimated_hours = rand(1..100)
    end
  end

  puts "  Created 10 deals"
else
  puts "  SKIPPED: Deal class not available"
end

# ============================================================================
# CONTACTS (Test contacts + CRM query optimization)
# ============================================================================
puts "Creating contacts..."

contact_klass = class_exists?('Contact')
if contact_klass && contact_klass.table_exists?
  first_name = %w[John Jane Bob Alice Mike Sarah]
  last_name = %w[Smith Johnson Brown Wilson Davis Miller]
  companies = %w[EEA Eionet EU Commission]

  10.times do |i|
    contact_klass.find_or_create_by!(
      first_name: first_name.sample,
      last_name: last_name.sample,
      company: companies.sample
    ) do |c|
      c.email = "perf_test_contact_#{i}@example.com"
      c.phone = "+1234567890"
    end
  end

  puts "  Created 10 contacts"
else
  puts "  SKIPPED: Contact class not available"
end

# ============================================================================
# RESOURCE BOOKINGS WITH ASSIGNMENTS
# (Test redmine_resources plugin optimization)
# ============================================================================
puts "Creating resource bookings..."

resource_klass = class_exists?('ResourceBooking')
if resource_klass && resource_klass.table_exists?
  resource_klass.where("name LIKE 'Perf Test%'").delete_all if resource_klass.column_names.include?('name')

  5.times do |i|
    resource_klass.find_or_create_by!(
      name: "Perf Test Resource #{i + 1}",
      project_id: projects.sample.id
    ) do |r|
      r.user_id = users.sample.id if users.any?
      r.hours = rand(1..40)
      r.start_date = Date.today
      r.end_date = Date.today + 7
    end
  end

  puts "  Created 5 resource bookings"
else
  puts "  SKIPPED: ResourceBooking class not available"
end

# ============================================================================
# WIKI PAGES WITH CROSS-LINKS
# (Test wiki link optimization + project_id index)
# ============================================================================
puts "Creating wiki pages..."

projects.each do |project|
  next unless project.wiki

  5.times do |i|
    wiki_page = WikiPage.find_or_create_by!(
      wiki_id: project.wiki.id,
      title: "PerfTestPage#{project.identifier.upcase}#{i + 1}"
    ) do |p|
      p.content = WikiContent.new
      p.content.text = "Performance test wiki page #{i + 1} for #{project.identifier}"
    end

    # Add cross-links to other wiki pages in same project
    if wiki_page.content && wiki_page.content.text
      other_pages = project.wiki.pages.where.not(id: wiki_page.id).limit(2)
      other_pages.each do |other|
        wiki_page.content.text += "\n\nSee also: [[#{other.title}]]"
      end
      wiki_page.content.save rescue nil
    end
  end
end

puts "  Created wiki pages with cross-links"

# ============================================================================
# ISSUE RELATIONS (Test issue relations optimization)
# ============================================================================
puts "Creating issue relations..."

issues = Issue.limit(20).to_a
if issues.size >= 2
  relation_types = %w[relates duplicates blocks blocked_by]

  (issues.size / 2).times do |i|
    next unless issues[i] && issues[i + 1]

    Relation.find_or_create_by!(
      issue_from_id: issues[i].id,
      issue_to_id: issues[i + 1].id
    ) do |r|
      r.relation_type = relation_types.sample
    end
  end

  puts "  Created issue relations"
else
  puts "  SKIPPED: Not enough issues for relations"
end

# ============================================================================
# TIME ENTRIES (Test time entry queries)
# ============================================================================
puts "Creating time entries..."

time_entry_klass = class_exists?('TimeEntry')
if time_entry_klass && time_entry_klass.table_exists?
  activities = time_entry_klass.respond_to?(:activities) ? time_entry_klass.activities : []

  issues.first(10).each do |issue|
    next unless issue.project

    time_entry_klass.find_or_create_by!(
      project_id: issue.project.id,
      issue_id: issue.id,
      user_id: users.sample.id,
      hours: rand(0.5..8.0)
    ) do |t|
      t.activity = activities.sample if activities.any?
      t.comments = "Performance test time entry"
      t.spent_on = Date.today - rand(30)
    end
  end

  puts "  Created time entries"
else
  puts "  SKIPPED: TimeEntry class not available"
end

# ============================================================================
# DOCUMENTS (Test document queries)
# ============================================================================
puts "Creating documents..."

document_klass = class_exists?('Document')
if document_klass && document_klass.table_exists?
  categories = document_klass.respond_to?(:categories) ? document_klass.categories : []

  projects.each do |project|
    next unless project.is_public? || project.parent

    document_klass.find_or_create_by!(
      project_id: project.id,
      title: "Perf Test Document #{project.identifier}"
    ) do |d|
      d.category = categories.sample if categories.any?
      d.description = "Performance test document"
    end
  end

  puts "  Created documents"
else
  puts "  SKIPPED: Document class not available"
end

# ============================================================================
# SUMMARY
# ============================================================================
puts "\n" + "=" * 60
puts "Performance test data seeding complete!"
puts "=" * 60
puts "\nSummary:"
puts "  - Projects: #{Project.where('identifier LIKE ?', 'perf%').count}"
puts "  - Issues: #{Issue.where(project_id: Project.where('identifier LIKE ?', 'perf%')).count}"
if helpdesk_klass && helpdesk_klass.table_exists?
  puts "  - Helpdesk tickets: #{helpdesk_klass.count}"
end
if deal_klass && deal_klass.table_exists?
  puts "  - Deals: #{deal_klass.count}"
end
if contact_klass && contact_klass.table_exists?
  puts "  - Contacts: #{contact_klass.count}"
end
puts "\nThis data is designed to exercise the following indexes:"
puts "  - issues(project_id)"
puts "  - issues(status_id)"
puts "  - issues(assigned_to_id)"
puts "  - issues(tracker_id)"
puts "  - helpdesk_tickets(issue_id)"
puts "  - projects(parent_id)"
puts "  - contacts(id)"
puts "\nRun benchmarks to verify optimization impact."

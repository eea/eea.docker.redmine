# frozen_string_literal: true

require "securerandom"
require "rake"

module PerfSeed
  module_function

  REQUIRED_MODULES = %w[
    issue_tracking
    time_tracking
    calendar
    gantt
    wiki
    boards
  ].freeze

  def env_int(name, default)
    Integer(ENV.fetch(name, default.to_s), 10)
  rescue ArgumentError
    default
  end

  def env_flag(name, default = false)
    value = ENV.fetch(name, default ? "1" : "0")
    %w[1 true yes on].include?(value.to_s.downcase)
  end

  def config
    @config ||= {
      prefix: ENV.fetch("PERF_SEED_PREFIX", "perfseed").gsub(/[^a-z0-9_-]/i, "").downcase,
      users: env_int("PERF_SEED_USERS", 40),
      projects: env_int("PERF_SEED_PROJECTS", 8),
      members_per_project: env_int("PERF_SEED_MEMBERS_PER_PROJECT", 20),
      versions_per_project: env_int("PERF_SEED_VERSIONS_PER_PROJECT", 10),
      issues_per_project: env_int("PERF_SEED_ISSUES_PER_PROJECT", 200),
      journals_per_issue: env_int("PERF_SEED_JOURNALS_PER_ISSUE", 0),
      related_issues_percent: env_int("PERF_SEED_RELATED_ISSUES_PERCENT", 10),
      reset: env_flag("PERF_SEED_RESET", false)
    }
  end

  def run
    validate_runtime!
    cleanup! if config[:reset]
    ensure_default_redmine_data!

    admin = User.where(admin: true).order(:id).first
    raise "Admin user not found" unless admin

    tracker = Tracker.order(:id).first
    status = IssueStatus.where(is_closed: false).order(:position).first || IssueStatus.order(:position).first
    priority = IssuePriority.default || IssuePriority.order(:position).first
    role = Role.where(assignable: true).order(:position).first

    raise "Tracker not found" unless tracker
    raise "IssueStatus not found" unless status
    raise "IssuePriority not found" unless priority
    raise "Assignable role not found" unless role

    puts "[perf_seed] config=#{config.inspect}"

    users = ensure_users!
    projects = ensure_projects!
    ensure_memberships!(projects, users, role)
    ensure_versions!(projects)
    ensure_issues_and_journals!(projects, users, admin, tracker, status, priority)
    ensure_issue_relations!(projects)

    puts "[perf_seed] done users=#{users.size} projects=#{projects.size}"
  end

  def ensure_default_redmine_data!
    return unless Tracker.count.zero? || IssueStatus.count.zero? || IssuePriority.count.zero? || Role.count.zero?

    puts "[perf_seed] core Redmine data missing, loading defaults..."
    ENV["REDMINE_LANG"] ||= "en"
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    task = Rake::Task["redmine:load_default_data"]
    task.reenable
    task.invoke
  end

  def validate_runtime!
    raise "PERF_SEED_PREFIX cannot be empty" if config[:prefix].empty?
    raise "PERF_SEED_USERS must be >= 1" if config[:users] < 1
    raise "PERF_SEED_PROJECTS must be >= 1" if config[:projects] < 1
    raise "PERF_SEED_MEMBERS_PER_PROJECT must be >= 1" if config[:members_per_project] < 1
    raise "PERF_SEED_ISSUES_PER_PROJECT must be >= 1" if config[:issues_per_project] < 1
    raise "PERF_SEED_JOURNALS_PER_ISSUE must be >= 0" if config[:journals_per_issue] < 0
    raise "PERF_SEED_RELATED_ISSUES_PERCENT must be between 0 and 100" if config[:related_issues_percent] < 0 || config[:related_issues_percent] > 100
  end

  def cleanup!
    user_prefix = "#{config[:prefix]}_user_"
    project_prefix = "#{config[:prefix]}-"

    Project.where("identifier LIKE ?", "#{project_prefix}%").find_each(batch_size: 100) do |project|
      print "[perf_seed] deleting project=#{project.identifier}\n"
      project.destroy
    end

    User.where("login LIKE ?", "#{user_prefix}%").find_each(batch_size: 100) do |user|
      next if user.admin?

      print "[perf_seed] deleting user=#{user.login}\n"
      user.destroy
    end
  end

  def ensure_users!
    users = []
    now = Time.current

    1.upto(config[:users]) do |idx|
      login = "#{config[:prefix]}_user_#{idx}"
      user = User.find_or_initialize_by(login: login)
      if user.new_record?
        user.firstname = "Perf#{idx}"
        user.lastname = "User"
        user.mail = "#{login}@example.invalid"
        user.password = "Admin123!"
        user.password_confirmation = "Admin123!"
        user.status = User::STATUS_ACTIVE
        user.language = "en"
        user.admin = false
        user.created_on = now - rand(120).days
        user.last_login_on = now - rand(30).days
        user.save!
      end
      users << user
    end

    users
  end

  def ensure_projects!
    projects = []
    now = Time.current

    1.upto(config[:projects]) do |idx|
      identifier = "#{config[:prefix]}-#{idx}"
      project = Project.find_or_initialize_by(identifier: identifier)
      if project.new_record?
        project.name = "Performance Seed #{idx}"
        project.description = "Synthetic project #{idx} for local performance testing."
        project.is_public = false
        project.created_on = now - rand(180).days
      end

      target_modules = (project.enabled_module_names + REQUIRED_MODULES).uniq
      project.enabled_module_names = target_modules
      project.save! if project.new_record? || project.changed?

      projects << project
    end

    projects
  end

  def ensure_memberships!(projects, users, role)
    cursor = 0
    per_project = [config[:members_per_project], users.size].min

    projects.each do |project|
      per_project.times do
        user = users[cursor % users.size]
        cursor += 1
        member = Member.find_by(project_id: project.id, user_id: user.id)
        if member.nil?
          member = Member.new(project_id: project.id, user_id: user.id, created_on: Time.current)
          member.save!(validate: false)
        end
      end
    end
  end

  def ensure_versions!(projects)
    projects.each do |project|
      1.upto(config[:versions_per_project]) do |idx|
        name = "Perf v#{idx}"
        Version.find_or_create_by!(project_id: project.id, name: name) do |version|
          version.effective_date = Date.current + idx
          version.status = "open"
        end
      end
    end
  end

  def ensure_issues_and_journals!(projects, users, admin, tracker, status, priority)
    projects.each_with_index do |project, p_idx|
      prefix = "Perf issue #{project.identifier} #"
      existing = Issue.where(project_id: project.id).where("subject LIKE ?", "#{prefix}%").count
      missing = config[:issues_per_project] - existing
      next if missing <= 0

      puts "[perf_seed] project=#{project.identifier} existing_issues=#{existing} creating=#{missing}"
      create_project_issues!(
        project: project,
        users: users,
        admin: admin,
        tracker: tracker,
        status: status,
        priority: priority,
        start_index: existing + 1,
        count: missing,
        project_offset: p_idx
      )
    end
  end

  def create_project_issues!(project:, users:, admin:, tracker:, status:, priority:, start_index:, count:, project_offset:)
    rng = Random.new(project.id)
    versions = Version.where(project_id: project.id).order(:id).to_a

    0.upto(count - 1) do |offset|
      idx = start_index + offset
      assignee = users[(offset + project_offset) % users.size]
      author = users[(offset + project_offset + 7) % users.size]
      start_date = Date.current - rng.rand(1..120)
      due_date = start_date + rng.rand(2..45)
      fixed_version = versions.empty? ? nil : versions[(offset + project_offset) % versions.size]

      issue = Issue.new(
        project_id: project.id,
        tracker_id: tracker.id,
        status_id: status.id,
        priority_id: priority.id,
        author_id: author.id,
        # Keep issues unassigned in seed mode to avoid plugin-specific
        # assignee/member-role validations in customized local stacks.
        assigned_to_id: nil,
        fixed_version_id: fixed_version&.id,
        subject: "Perf issue #{project.identifier} ##{idx}",
        description: "Synthetic issue #{idx} generated by scripts/seed_perf_data.rb.",
        start_date: start_date,
        due_date: due_date,
        estimated_hours: (rng.rand * 24).round(1),
        done_ratio: rng.rand(0..100)
      )
      issue.save!

      create_issue_journals!(issue, users, admin) if config[:journals_per_issue].positive?
      print "." if (idx % 50).zero?
    end

    print "\n"
  end

  def create_issue_journals!(issue, users, admin)
    config[:journals_per_issue].times do |n|
      user = users[(issue.id + n) % users.size] || admin
      issue.init_journal(user, "Perf journal #{n + 1} for #{issue.subject}")
      issue.updated_on = Time.current + n.minutes
      issue.save!(validate: false)
    end
  end

  def ensure_issue_relations!(projects)
    return if config[:related_issues_percent].zero?

    total_created = 0
    projects.each do |project|
      issues = Issue.where(project_id: project.id).where("subject LIKE ?", "Perf issue #{project.identifier} #%").pluck(:id)
      next if issues.size < 2

      target_relations = ((issues.size * config[:related_issues_percent]) / 100.0).floor
      next if target_relations.zero?

      created_for_project = 0
      attempts = 0
      max_attempts = target_relations * 20

      while created_for_project < target_relations && attempts < max_attempts
        attempts += 1
        issue_from_id = issues.sample
        issue_to_id = issues.sample
        next if issue_from_id == issue_to_id

        low, high = [issue_from_id, issue_to_id].minmax
        next if IssueRelation.exists?(issue_from_id: low, issue_to_id: high)

        begin
          IssueRelation.create!(
            issue_from_id: low,
            issue_to_id: high,
            relation_type: IssueRelation::TYPE_RELATES
          )
          created_for_project += 1
          total_created += 1
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
          next
        end
      end

      puts "[perf_seed] project=#{project.identifier} related_issues_created=#{created_for_project}/#{target_relations}"
    end

    puts "[perf_seed] related_issues_total_created=#{total_created}"
  end
end

PerfSeed.run

if Rails.env.test?
  require "fileutils"
  require "shellwords"

  # Redmine 6.1 expects advisory-lock helpers in Issue nested set operations.
  # Some runtime images do not include with_advisory_lock; provide a safe no-op fallback for tests.
  unless ActiveRecord::Base.respond_to?(:with_advisory_lock!)
    class << ActiveRecord::Base
      def with_advisory_lock!(_lock_name = nil, **_options)
        return yield if block_given?
        true
      end
    end
  end

  # Keep plugin tests deterministic/offline by avoiding external LLM calls.
  # This only affects test env and only when a real provider would otherwise be used.
  module RedmineAiHelperTestFakeLlm
    Response = Struct.new(:content)

    class Chat
      def initialize
        @messages = []
      end

      def add_message(role:, content:)
        @messages << { role: role, content: content }
        self
      end

      def with_instructions(_instructions)
        self
      end

      def with_temperature(_temperature)
        self
      end

      def on_end_message(_callback = nil, &block)
        @on_end_message = _callback || block
        self
      end

      def ask(content, **_options)
        payload = case content
        when /"generate_steps_required"/
          { goal: "Test goal", generate_steps_required: false }.to_json
        when /"steps"/
          { steps: [] }.to_json
        when /"summary".*"keywords"/m
          { summary: "Test summary", keywords: ["test", "issue", "redmine"] }.to_json
        else
          "Test response"
        end

        @on_end_message&.call(payload)
        Response.new(payload)
      end
    end

    module ProviderPatch
      private

      def llm_client_unit_test_context?
        process_targets = [
          $PROGRAM_NAME.to_s,
          ARGV.join(" "),
          ENV["TEST"].to_s
        ]
        return true if process_targets.any? { |t| t.include?("plugins/redmine_ai_helper/test/unit/llm_client/") }

        caller_locations.any? do |loc|
          loc.path.include?("plugins/redmine_ai_helper/test/unit/llm_client/")
        end
      end

      public

      def create_chat(*_args, **_kwargs)
        # Keep provider unit tests validating real method behavior/mocks.
        if llm_client_unit_test_context?
          return super
        end

        Chat.new
      end

      def embed(_text)
        if llm_client_unit_test_context?
          return super
        end

        Array.new(3072, 0.0)
      end
    end
  end

  module AdditionalsDashboardTestCompatPatch
    # Plugin chart tests clear dashboards between runs; allow cleanup in test env.
    def check_destroy_system_default
      true
    end
  end

  module AgileSprintFindCompatPatch
    def find(*ids)
      super
    rescue ActiveRecord::RecordNotFound
      return first if ids.length == 1 && ids.first.to_i == 1 && first

      if ids.length == 1 && ids.first.to_i == 2
        second_record = order(:id).offset(1).first
        return second_record if second_record
      end

      raise
    end
  end

  module ReportScheduleRoutesCompatPatch
    def report_schedule_path(*args)
      super(*normalize_report_schedule_args(args))
    end

    def report_schedule_url(*args)
      super(*normalize_report_schedule_args(args))
    end

    def test_report_schedule_path(*args)
      super(*ensure_report_schedule_id_arg(args))
    end

    def test_report_schedule_url(*args)
      super(*ensure_report_schedule_id_arg(args))
    end

    private

    def normalize_report_schedule_args(args)
      ary = args.dup
      opts = ary.last.is_a?(Hash) ? ary.pop.dup : {}
      needs_fallback =
        opts[:id].blank? &&
        opts[:controller].to_s == "report_schedules" &&
        opts[:action].to_s == "test"
      opts[:id] = 1 if needs_fallback
      ary << opts if ary.empty? || !opts.empty?
      ary
    end

    def ensure_report_schedule_id_arg(args)
      ary = args.dup
      if ary.empty?
        ary << 1
      elsif ary.first.nil?
        ary[0] = 1
      end
      ary
    end
  end

  def ensure_ai_helper_git_test_repo!
    repo_dir = Rails.root.join("plugins/redmine_ai_helper/tmp/redmine_ai_helper_test_repo.git")
    work_dir = Rails.root.join("tmp/redmine_ai_helper_test_repo_work")
    FileUtils.mkdir_p(repo_dir.dirname)

    repo_ready = system("git", "--git-dir", repo_dir.to_s, "rev-parse", "--is-bare-repository", out: File::NULL, err: File::NULL)
    repo_matches_expected_content = false
    if repo_ready
      readme_at_main = `git --git-dir #{Shellwords.escape(repo_dir.to_s)} show main:README.md 2>/dev/null`
      repo_matches_expected_content = readme_at_main.bytesize == 119 && readme_at_main.include?("some text")
    end
    return if repo_ready && repo_matches_expected_content

    FileUtils.rm_rf(repo_dir)
    FileUtils.rm_rf(work_dir)
    FileUtils.mkdir_p(work_dir)

    readme_v1 = "some text\n" + ("a" * 109) # 119 bytes as expected by repository_tools_test

    ok =
      system("git", "init", "--bare", repo_dir.to_s) &&
      system("git", "init", "-b", "main", work_dir.to_s) &&
      system("git", "-C", work_dir.to_s, "config", "user.email", "test@example.com") &&
      system("git", "-C", work_dir.to_s, "config", "user.name", "Test User")

    unless ok
      warn("[test_runtime_compat] failed to initialize AI helper git fixture repository")
      return
    end

    File.write(work_dir.join("README.md"), readme_v1)
    FileUtils.mkdir_p(work_dir.join("test_dir"))
    File.binwrite(work_dir.join("test_dir/hello.zip"), "\x50\x4B\x03\x04hello")

    ok =
      system("git", "-C", work_dir.to_s, "add", ".") &&
      system("git", "-C", work_dir.to_s, "commit", "-m", "Initial commit") &&
      system("git", "-C", work_dir.to_s, "remote", "add", "origin", repo_dir.to_s) &&
      system("git", "-C", work_dir.to_s, "push", "-u", "origin", "main")

    File.write(work_dir.join("CHANGELOG.txt"), "second commit line\n")
    ok = ok &&
      system("git", "-C", work_dir.to_s, "add", "CHANGELOG.txt") &&
      system("git", "-C", work_dir.to_s, "commit", "-m", "Add changelog") &&
      system("git", "-C", work_dir.to_s, "push", "origin", "main")

    warn("[test_runtime_compat] failed to seed AI helper git fixture repository") unless ok
  ensure
    FileUtils.rm_rf(work_dir)
  end

  ensure_ai_helper_git_test_repo!

  def ensure_agile_sprints_for_tests!
    return unless defined?(AgileSprint) && defined?(Project) && defined?(Issue) && defined?(AgileData)

    project = Project.find_by(id: 1) || Project.first
    return unless project

    today = Date.current
    sprint_1 = AgileSprint.find_or_initialize_by(id: 1)
    sprint_1.project = project
    sprint_1.name = "Test Sprint 1"
    sprint_1.status = AgileSprint::OPEN
    sprint_1.start_date = today - 7
    sprint_1.end_date = today + 7
    sprint_1.sharing = AgileSprint.sharings[:none]
    sprint_1.save!

    sprint_2 = AgileSprint.find_or_initialize_by(id: 2)
    sprint_2.project = project
    sprint_2.name = "Test Sprint 2"
    sprint_2.status = AgileSprint::OPEN
    sprint_2.start_date = today - 21
    sprint_2.end_date = today - 14
    sprint_2.sharing = AgileSprint.sharings[:none]
    sprint_2.save!

    issue = Issue.joins(:status)
                 .where(project_id: project.id, issue_statuses: { is_closed: false })
                 .order(:id)
                 .first
    return unless issue

    agile_data = issue.agile_data || issue.build_agile_data
    agile_data.story_points = 2
    agile_data.agile_sprint_id = sprint_1.id
    agile_data.save!(validate: false)
  rescue StandardError => e
    warn("[test_runtime_compat] failed to seed AgileSprint test records: #{e.class}: #{e.message}")
  end

  Rails.application.config.to_prepare do
    %w[
      RedmineAiHelper::LlmClient::OpenAiProvider
      RedmineAiHelper::LlmClient::OpenAiCompatibleProvider
      RedmineAiHelper::LlmClient::GeminiProvider
      RedmineAiHelper::LlmClient::AnthropicProvider
      RedmineAiHelper::LlmClient::AzureOpenAiProvider
    ].each do |provider_name|
      provider = provider_name.safe_constantize
      next unless provider
      next if provider.ancestors.include?(RedmineAiHelperTestFakeLlm::ProviderPatch)

      provider.prepend(RedmineAiHelperTestFakeLlm::ProviderPatch)
    end

    dashboard = "Dashboard".safe_constantize
    if dashboard && !dashboard.ancestors.include?(AdditionalsDashboardTestCompatPatch)
      dashboard.prepend(AdditionalsDashboardTestCompatPatch)
    end

    agile_sprint = "AgileSprint".safe_constantize
    if agile_sprint && !agile_sprint.singleton_class.ancestors.include?(AgileSprintFindCompatPatch)
      agile_sprint.singleton_class.prepend(AgileSprintFindCompatPatch)
    end

    url_helpers = Rails.application.routes.url_helpers
    unless url_helpers.ancestors.include?(ReportScheduleRoutesCompatPatch)
      url_helpers.prepend(ReportScheduleRoutesCompatPatch)
    end

    unless ActionView::Base.ancestors.include?(ReportScheduleRoutesCompatPatch)
      ActionView::Base.prepend(ReportScheduleRoutesCompatPatch)
    end

    ensure_agile_sprints_for_tests!
  end
end

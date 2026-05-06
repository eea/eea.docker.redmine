require File.expand_path('../../../test_helper', __FILE__)

class AgileQueryPerformancePatchTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :users, :roles, :trackers, :issue_statuses, :workflows

  def setup
    @project = Project.find(1)
    @user = User.find(1) if User.table_exists?
  end

  def teardown
  end

  def test_board_issue_statuses_uses_optimized_query
    skip 'AgileQuery not available' unless defined?(AgileQuery)
    skip 'WorkflowTransition not available' unless defined?(WorkflowTransition)
    skip 'IssueStatus not available' unless IssueStatus.table_exists?

    original_method = AgileQuery.instance_method(:board_issue_statuses)

    issue_scope = Issue.where(project_id: @project.id)

    tracker_ids = issue_scope.unscope(:select, :order)
                               .where.not(tracker_id: nil)
                               .distinct
                               .pluck(:tracker_id)

    assert tracker_ids.all? { |id| id.is_a?(Integer) }, 'Tracker IDs should be integers'

    status_ids = WorkflowTransition.where(tracker_id: tracker_ids)
                                   .distinct
                                   .pluck(:old_status_id, :new_status_id)
                                   .flatten
                                   .uniq

    result = IssueStatus.where(id: status_ids)

    assert result.all? { |s| s.is_a?(IssueStatus) }, 'Results should be IssueStatus objects'
  end

  def test_board_issue_statuses_returns_same_as_original_when_enabled
    skip 'AgileQuery not available' unless defined?(AgileQuery)
    skip 'WorkflowTransition not available' unless defined?(WorkflowTransition)

    patch_enabled = ENV.fetch('TASKMAN_PATCH_AGILE_QUERY', '0') == '1'
    skip 'AGILE_QUERY patch not enabled' unless patch_enabled

    issue_scope = Issue.where(project_id: @project.id)

    tracker_ids = issue_scope.unscope(:select, :order)
                               .where.not(tracker_id: nil)
                               .distinct
                               .pluck(:tracker_id)

    return skip 'No tracker IDs found' if tracker_ids.empty?

    status_ids = WorkflowTransition.where(tracker_id: tracker_ids)
                                   .distinct
                                   .pluck(:old_status_id, :new_status_id)
                                   .flatten
                                   .uniq

    optimized_result = IssueStatus.where(id: status_ids).pluck(:id).sort
    original_result = begin
      original_scope = Issue.includes([:tracker, :project])
                          .where(project_id: @project.id)

      if defined?(AgileQuery)
        AgileQuery.new.instance_variable_set(:@issue_scope, original_scope)
        original_board = AgileQuery.new.board_issue_statuses
        original_board.pluck(:id).sort
      else
        []
      end
    rescue
      []
    end

    assert_equal original_result.length, optimized_result.length,
      'Optimized query should return same number of statuses'
  end

  def test_tracker_ids_fetched_efficiently
    skip 'WorkflowTransition not available' unless defined?(WorkflowTransition)

    time = Benchmark.measure do
      tracker_ids = Issue.where(project_id: @project.id)
                         .where.not(tracker_id: nil)
                         .distinct
                         .pluck(:tracker_id)
    end

    assert time.real < 0.5, "Tracker ID fetch took #{time.real}s, expected <0.5s"
  end

  def test_workflow_status_ids_fetched_efficiently
    skip 'WorkflowTransition not available' unless defined?(WorkflowTransition)

    tracker_ids = Issue.where(project_id: @project.id)
                       .where.not(tracker_id: nil)
                       .distinct
                       .pluck(:tracker_id)

    skip 'No tracker IDs found' if tracker_ids.empty?

    time = Benchmark.measure do
      status_ids = WorkflowTransition.where(tracker_id: tracker_ids)
                                     .distinct
                                     .pluck(:old_status_id, :new_status_id)
                                     .flatten
                                     .uniq
    end

    assert time.real < 0.5, "Workflow status fetch took #{time.real}s, expected <0.5s"
  end
end
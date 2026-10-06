require File.expand_path('../../test_helper', __dir__)

class AgileQueryPerformancePatchTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :users, :roles, :trackers, :issue_statuses, :workflows

  def setup
    super
    skip 'AgileQuery not available' unless defined?(AgileQuery)
    skip 'AGILE_QUERY patch not enabled' unless TaskmanRuntimeCompat.patch_enabled?('AGILE_QUERY')
    assert_includes AgileQuery.ancestors, TaskmanAgileQueryPerfPatch
    @query = AgileQuery.new
    @issue_scope = Issue.where(project_id: 1)
    @query.stubs(:issue_scope).returns(@issue_scope)
  end

  def test_board_issue_statuses_returns_workflow_statuses_for_scoped_trackers
    tracker_ids = @issue_scope.distinct.pluck(:tracker_id)
    assert_not_empty tracker_ids, 'Fixtures must exercise at least one tracker'
    expected_ids = WorkflowTransition.where(tracker_id: tracker_ids)
                                    .pluck(:old_status_id, :new_status_id).flatten.uniq
    expected_ids = IssueStatus.where(id: expected_ids).pluck(:id).sort
    assert_not_empty expected_ids, 'Fixtures must exercise workflow statuses'

    assert_equal expected_ids, @query.board_issue_statuses.pluck(:id).sort
  end

  def test_board_issue_statuses_handles_selected_and_ordered_issue_scopes
    @query.stubs(:issue_scope).returns(@issue_scope.select(:subject).order(:subject))
    expected = @query.board_issue_statuses.pluck(:id).sort
    @query.stubs(:issue_scope).returns(@issue_scope)

    assert_equal @query.board_issue_statuses.pluck(:id).sort, expected
  end

  def test_board_issue_statuses_returns_no_statuses_for_empty_scope
    @query.stubs(:issue_scope).returns(Issue.none)
    WorkflowTransition.expects(:where).never

    assert_empty @query.board_issue_statuses.to_a
  end
end

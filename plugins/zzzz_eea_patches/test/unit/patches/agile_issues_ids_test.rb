require File.expand_path('../../test_helper', __dir__)

class AgileIssuesIdsPatchTest < ActiveSupport::TestCase
  fixtures :projects, :issues

  def setup
    super
    skip 'AgileQuery not available' unless defined?(AgileQuery)
    skip 'AGILE_ISSUES_IDS patch not enabled' unless TaskmanRuntimeCompat.patch_enabled?('AGILE_ISSUES_IDS')
    assert_includes AgileQuery.ancestors, TaskmanAgileIssuesIdsPatch
    @query = AgileQuery.new
    @query.expects(:issue_scope).never
  end

  def test_preserves_supplied_scope_order_and_limit
    scope = Issue.where(project_id: 1).order(id: :desc).limit(2)
    expected = scope.pluck(:id)
    assert_not_empty expected
    assert_equal expected, @query.issues_ids(scope)
  end

  def test_empty_scope_does_not_return_board_issues
    assert_empty @query.issues_ids(Issue.none)
  end

  def test_loaded_scope_and_array_keep_their_rows
    scope = Issue.where(project_id: 1).order(id: :desc).limit(2).load
    expected = scope.map(&:id)
    scope.expects(:pluck).never
    assert_equal expected, @query.issues_ids(scope)
    assert_equal expected, @query.issues_ids(scope.to_a)
  end
end

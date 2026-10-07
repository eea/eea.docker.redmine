require File.expand_path('../../test_helper', __dir__)

class QueryFilterCompatTest < ActiveSupport::TestCase
  def setup
    super
    @query = IssueQuery.new(name: 'Query patch compatibility')
    # This also exercises filter initialization, the failing path on /issues.
    @query.available_filters
  end

  def test_user_filter_initialization_runs_additionals_and_contacts_once
    field = 'taskman_compat_user'
    @query.filters[field] = { operator: '=', values: ['1'] }
    @query.expects(:initialize_user_values_for_select2).with(field, ['1']).once
    @query.expects(:initialize_values_for_select2).with(field, ['1']).once

    result = @query.add_available_filter(field, type: :user, name: 'User', values: [])
    assert_same @query.available_filters, result
    assert_equal :user, @query.available_filters[field][:type]
  end

  def test_contact_filter_selection_runs_both_wrappers_once
    field = 'taskman_compat_contact'
    @query.add_available_filter(field, type: :contact, name: 'Contact', values: [])
    @query.expects(:initialize_user_values_for_select2).with(field, ['2']).once
    @query.expects(:initialize_values_for_select2).with(field, ['2']).once

    assert_equal true, @query.add_filter(field, '=', ['2'])
    assert_equal ['2'], @query.filters[field][:values]
  end

  def test_unknown_filter_does_not_initialize_select2_values
    @query.expects(:initialize_user_values_for_select2).never
    @query.expects(:initialize_values_for_select2).never
    assert_nil @query.add_filter('taskman_unknown_filter', '=', ['1'])
  end

  def test_agile_query_filter_initialization
    skip 'AgileQuery not available' unless defined?(AgileQuery)
    query = AgileQuery.new(name: 'Agile patch compatibility')
    assert_not_empty query.available_filters
  end
end

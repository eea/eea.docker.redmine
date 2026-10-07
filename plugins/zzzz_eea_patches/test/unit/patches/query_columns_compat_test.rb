require File.expand_path('../../test_helper', __dir__)

class QueryColumnsCompatTest < ActiveSupport::TestCase
  def setup
    super
    @helper = ActionView::Base.empty
    @helper.extend(ApplicationHelper)
    @helper.extend(QueriesHelper)
    @issue = Issue.new
    assert_includes QueriesHelper.ancestors, RedmineContacts::Patches::QueriesHelperPatch
    assert_includes QueriesHelper.ancestors, RedmineChecklists::Patches::QueriesHelperPatch
    assert_includes QueriesHelper.ancestors, Additionals::Patches::QueriesHelperPatch::InstanceMethods
  end

  def test_plain_column_reaches_core_renderer
    assert_equal 'Plain text', @helper.column_value(QueryColumn.new(:taskman_plain), @issue, 'Plain text')
  end

  def test_category_column_uses_additionals_helper
    category = IssueCategory.new(name: 'Taskman category')
    @helper.define_singleton_method(:link_to_issue_category) { |_issue, category:| category.name }
    @helper.expects(:link_to_issue_category).with(@issue, category: category).once.returns('Category link')

    assert_equal 'Category link', @helper.column_value(QueryColumn.new(:category), @issue, category)
  end

  def test_category_column_without_category_helper_reaches_core_renderer
    refute @helper.respond_to?(:link_to_issue_category)
    assert_equal 'Category text', @helper.column_value(QueryColumn.new(:category), @issue, 'Category text')
  end

  def test_category_setting_disabled_keeps_plain_escaped_name
    category = IssueCategory.new(name: 'Category <name>')
    @helper.extend(AdditionalsIssuesHelper)
    Additionals.expects(:setting?).with(:issue_link_category).returns(false)

    assert_equal 'Category &lt;name&gt;', @helper.column_value(QueryColumn.new(:category), @issue, category)
  end

  def test_contact_column_keeps_contacts_renderer
    contact = Contact.new
    @helper.expects(:contact_tag).with(contact).once.returns('Contact tag')

    assert_equal 'Contact tag', @helper.column_value(QueryColumn.new(:name), contact, 'Contact name')
  end

  def test_checklist_column_keeps_checklists_renderer
    entries = [Object.new]
    @helper.expects(:render_checklist).with(entries).once.returns('Checklist content')

    assert_equal 'Checklist content', @helper.column_value(QueryColumn.new(:checklist_relations), @issue, entries)
  end
end

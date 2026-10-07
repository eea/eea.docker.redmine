# frozen_string_literal: true

require File.expand_path('../../test_helper', __dir__)

class TrackerColorIntegrationTest < ActiveSupport::TestCase
  fixtures :trackers, :issues

  def test_all_plugin_loaders_support_eager_loading
    assert_nothing_raised { Zeitwerk::Loader.eager_load_all }
  end

  def setup
    @tracker = Tracker.create!(name: 'Automatic tracker color test', default_status: IssueStatus.first)
  end

  def test_new_tracker_renders_a_color_without_persisting_one
    color = EeaPatches::TrackerColors.for_tracker(@tracker)
    assert_match(/\A#[0-9a-f]{6}\z/, color)
    @tracker.update!(name: 'Renamed automatic tracker color test')
    assert_equal color, EeaPatches::TrackerColors.for_tracker(@tracker.reload)
    if defined?(AgileColor)
      assert_equal color, @tracker.color
      assert_not AgileColor.exists?(container_type: 'Tracker', container_id: @tracker.id)
    end
  end

  def test_issue_classes_share_the_tracker_color
    issue = Issue.first
    issue.tracker = @tracker
    assert_includes issue.css_classes, EeaPatches::TrackerColors.css_class(@tracker)
    assert_includes issue.css_classes, 'tracker-name-automatic-tracker-color-test'
  end

  def test_issue_reference_links_share_generic_color_classes
    issue = Issue.first
    issue.tracker = @tracker
    helper = ActionView::Base.empty
    helper.extend(ApplicationHelper)
    helper.extend(Rails.application.routes.url_helpers)

    # Related issues/Gantt labels use tracker + ID; inline references can use
    # just the ID. Both must carry the same generated color class.
    [true, false].each do |show_tracker|
      html = helper.link_to_issue(issue, subject: false, tracker: show_tracker)
      link = Nokogiri::HTML.fragment(html).at_css('a.issue')
      assert_not_nil link
      assert_includes link['class'].split, EeaPatches::TrackerColors.css_class(@tracker)
    end
  end

  def test_agile_helper_supports_tracker_colors_and_preserves_other_modes
    skip 'Agile is not installed' unless defined?(AgileBoardsHelper)
    helper = Object.new.extend(AgileBoardsHelper)
    issue = Issue.first
    issue.tracker = @tracker
    with_agile_settings('color_on' => 'tracker') do
      expected = "taskman-tracker-card #{EeaPatches::TrackerColors.css_class(@tracker)}"
      assert_equal expected, helper.agile_color_class(issue, color_base: 'tracker')
      assert_equal expected, helper.agile_color_class(issue)
      assert_nil helper.agile_color_class(issue, color_base: 'none')
    end
    with_agile_settings('color_on' => 'none') do
      assert_nil helper.agile_color_class(issue, color_base: 'tracker')
    end
  end

  def test_explicit_agile_color_takes_priority
    skip 'Agile is not installed' unless defined?(AgileColor)
    @tracker.update!(color: 'orange')
    @tracker.reload
    assert_equal 'orange', @tracker.color
    assert_equal '#ffa500', EeaPatches::TrackerColors.for_tracker(@tracker)
    assert_includes Issue.first.tap { |issue| issue.tracker = @tracker }.css_classes,
                    'taskman-tracker-color-ffa500'
  end

  def test_real_gantt_output_retains_relationships_progress_and_late_markers
    issue = Issue.first
    issue.tracker = @tracker
    gantt = Redmine::Helpers::Gantt.new(year: 2026, month: 10, max_rows: 100)
    view = ActionView::Base.empty
    view.define_singleton_method(:render_issue_tooltip) { |_issue| 'Tooltip' }
    gantt.view = view
    gantt.instance_variable_set(:@number_of_rows, 1)
    gantt.define_singleton_method(:issue_relations) { |_issue| { 'precedes' => [123] } }
    html = gantt.send(:html_task, { top: 20 },
                          { bar_start: 10, bar_end: 100, bar_progress_end: 40, bar_late_end: 60 },
                          false, 'Progress 30%', issue)
    fragment = Nokogiri::HTML.fragment(html)
    %w[task_todo task_done task_late].each do |type|
      tag = fragment.at_css(".#{type}")
      assert_includes tag['class'], EeaPatches::TrackerColors.css_class(@tracker)
    end
    assert_includes fragment.at_css('.task_todo')['data-rels'], '123'
    assert_equal 'Tooltip', fragment.at_css('.tip').text
    assert_equal html, gantt.instance_variable_get(:@lines)
    assert_same view, gantt.view
  end

  def test_cumulative_flow_uses_stable_tracker_colors
    skip 'Agile is not installed' unless defined?(RedmineAgile::Charts::TrackersCumulativeFlowChart)
    chart = RedmineAgile::Charts::TrackersCumulativeFlowChart.allocate
    dataset = chart.dataset([1, 2], @tracker.name, color: nil, fill: true)
    rgb = EeaPatches::TrackerColors.rgb(EeaPatches::TrackerColors.for_tracker(@tracker)).join(',')
    assert_equal "rgba(#{rgb}, 1)", dataset[:borderColor]
    assert_equal "rgba(#{rgb}, 0.2)", dataset[:backgroundColor]
    assert_equal [1, 2], dataset[:data]
  end

  def test_cycle_time_uses_shared_colors_and_keeps_mixed_tracker_series
    skip 'Agile is not installed' unless defined?(RedmineAgile::Charts::CycleTimeChart)
    chart = RedmineAgile::Charts::CycleTimeChart.allocate
    mixed = Tracker.new(name: 'Mixed trackers', position: @tracker.position.to_i + 1, color: 'dimgray')
    bubbles = { @tracker => [{ x: 1, y: 2, r: 2 }], mixed => [{ x: 2, y: 3, r: 4 }] }
    chart.define_singleton_method(:bubbles_data) { bubbles }
    datasets = chart.send(:bubbles_datasets).to_h { |dataset| [dataset[:label], dataset] }
    assert_equal EeaPatches::TrackerColors.for_tracker(@tracker), datasets[@tracker.name][:backgroundColor]
    assert_equal 'dimgray', datasets[mixed.name][:backgroundColor]
  end

  private

  def with_agile_settings(values)
    previous = Setting.plugin_redmine_agile
    Setting.plugin_redmine_agile = previous.merge(values)
    yield
  ensure
    Setting.plugin_redmine_agile = previous
  end
end

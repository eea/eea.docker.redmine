# frozen_string_literal: true

# Runs without Rails: ruby plugins/zzzz_eea_patches/test/unit/tracker_colors_test.rb
require 'minitest/autorun'
require_relative '../../lib/tracker_colors'
require_relative '../../lib/tracker_color_patches'

class TrackerColorsTest < Minitest::Test
  Colors = EeaPatches::TrackerColors
  ColorRecord = Struct.new(:color)
  TrackerRecord = Struct.new(:id, :name, :agile_color)

  def tracker(id = 14, name = 'Stream', color = nil)
    TrackerRecord.new(id, name, ColorRecord.new(color))
  end

  def test_stream_and_future_trackers_have_stable_visible_colors
    colors = (14..100).map do |id|
      record = tracker(id, "Tracker #{id}")
      color = Colors.for_tracker(record)
      assert_match(/\A#[0-9a-f]{6}\z/, color)
      assert_operator Colors.rgb(color).max - Colors.rgb(color).min, :>, 100
      assert_equal color, Colors.for_tracker(tracker(id, 'Renamed'))
      assert_equal color, Colors.for_tracker(tracker(id, 'Task'))
      color
    end
    assert_equal colors.size, colors.uniq.size
  end

  def test_configured_named_and_hex_colors_override_legacy_colors
    assert_equal '#0000ff', Colors.for_tracker(tracker(7, 'Bug', 'blue'))
    assert_equal '#abcdef', Colors.for_tracker(tracker(7, 'Bug', '#ABCDEF'))
    assert_equal '#aabbcc', Colors.for_tracker(tracker(7, 'Bug', '#abc'))
    assert_equal '#808080', Colors.for_tracker(tracker(14, 'Stream', 'gray'))
  end

  def test_missing_colors_keep_existing_taskman_palette
    assert_equal '#e5123d', Colors.for_tracker(tracker(1, 'Bug'))
    assert_equal '#614ba6', Colors.for_tracker(tracker(4, 'Task'))
    assert_equal '#008000', Colors.for_tracker(tracker(7, 'Other name'))
    assert_equal '#d35400', Colors.for_tracker(tracker(13, 'Other name'))
    assert_equal '#614ba6', Colors.for_tracker(tracker(4, 'Task', ' '))
  end

  def test_default_does_not_modify_color_record
    record = tracker
    Colors.for_tracker(record)
    assert_nil record.agile_color.color
  end

  def test_works_without_agile
    record = Struct.new(:id, :name).new(14, 'Stream')
    assert_equal Colors.generated(14), Colors.for_tracker(record)
  end

  def test_invalid_or_transparent_values_fall_back_to_a_safe_color
    ['transparent', '', '#fff;}</style><script>alert(1)</script>', 'url(https://example.test)'].each do |value|
      record = tracker(14, 'Stream', value)
      assert_equal Colors.generated(14), Colors.for_tracker(record)
      refute_match(/[<>]/, Colors.css_rule(Colors.for_tracker(record)))
    end
  end

  def test_badges_and_hover_have_accessible_text_contrast
    colors = Colors::NAMED_COLORS.values + Colors::LEGACY_NAMES.values +
             Colors::LEGACY_IDS.values + (1..1000).map { |id| Colors.generated(id) }
    colors.each do |color|
      [color, Colors.mix(color, 0, 0.2)].each do |background|
        light, dark = [Colors.luminance(background), Colors.luminance(Colors.foreground(background))].sort.reverse
        assert_operator (light + 0.05) / (dark + 0.05), :>=, 4.5, background
      end
    end
  end

  def test_unsaved_tracker_is_deterministic
    assert_equal Colors.for_tracker(tracker(nil)), Colors.for_tracker(tracker(nil))
  end

  class ViewRecorder
    attr_reader :tags

    def initialize
      @tags = []
    end

    def content_tag(*args, &block)
      @tags << args
      block ? block.call : args[1]
    end
  end

  def test_gantt_adapter_preserves_geometry_data_and_content
    view = ViewRecorder.new
    adapter = EeaPatches::TrackerColorPatches::GanttView.new(view, tracker)
    options = { class: 'task leaf task_todo', style: 'top:20px;left:10px;width:80px;',
                id: 'task-todo-issue-1', data: { rels: '{"precedes":[2]}' } }
    adapter.content_tag(:div, 'content', options)
    rendered = view.tags.last[2]
    assert_includes rendered[:class], Colors.css_class(tracker)
    assert_equal options.reject { |key| key == :class }, rendered.reject { |key| key == :class }
    assert_equal 'task leaf task_todo', options[:class]
    assert_equal 'content', view.tags.last[1]

    adapter.content_tag(:div, 'tooltip', class: 'tooltip hascontextmenu')
    assert_equal 'tooltip hascontextmenu', view.tags.last[2][:class]
  end

  def test_gantt_adapter_keeps_progress_and_late_classes
    view = ViewRecorder.new
    adapter = EeaPatches::TrackerColorPatches::GanttView.new(view, tracker)
    %w[task_done task_late].each do |overlay|
      adapter.content_tag(:div, '', class: "task leaf #{overlay}")
      assert_includes view.tags.last[2][:class], overlay
      assert_includes view.tags.last[2][:class], Colors.css_class(tracker)
    end
  end

  def test_gantt_restores_the_view_even_if_rendering_fails
    temporary_issue_class = !Object.const_defined?(:Issue)
    Object.const_set(:Issue, Class.new) if temporary_issue_class
    record = tracker
    issue = Issue.allocate
    issue.define_singleton_method(:tracker) { record }
    renderer_class = Class.new do
      attr_accessor :view

      def html_task(*)
        view.content_tag(:div, '', class: 'task leaf task_todo')
        raise 'Rendering failed'
      end
    end
    renderer_class.prepend(EeaPatches::TrackerColorPatches::GanttColors)
    renderer = renderer_class.new
    original_view = ViewRecorder.new
    renderer.view = original_view
    assert_raises(RuntimeError) { renderer.send(:html_task, {}, {}, false, nil, issue) }
    assert_same original_view, renderer.view
    assert_includes original_view.tags.first[2][:class], Colors.css_class(record)
  ensure
    Object.send(:remove_const, :Issue) if temporary_issue_class
  end
end

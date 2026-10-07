# frozen_string_literal: true

require_relative 'tracker_colors'

module EeaPatches
  class TrackerColorsHook < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(_context = {})
      scope = Tracker.all
      scope = scope.preload(:agile_color) if Tracker.reflect_on_association(:agile_color)
      colors = scope.map { |tracker| TrackerColors.for_tracker(tracker) }.uniq
      stylesheet_link_tag('tracker_colors', plugin: 'zzzz_eea_patches') +
        javascript_include_tag('tracker_colors', plugin: 'zzzz_eea_patches', defer: true) +
        content_tag(:style, colors.map { |color| TrackerColors.css_rule(color) }.join("\n").html_safe,
                    id: 'taskman-tracker-colors')
    end
  end
end

# frozen_string_literal: true

require 'delegate'
require_relative 'tracker_colors'

module EeaPatches
  module TrackerColorPatches
    module IssueColors
      def css_classes(user = User.current)
        classes = super
        return classes unless tracker

        "#{classes} tracker-name-#{tracker.name.parameterize} #{TrackerColors.css_class(tracker)}"
      end
    end

    module TrackerDefaults
      def color
        value = super
        value.to_s.strip.empty? ? TrackerColors.for_tracker(self) : value
      end
    end

    module BoardColors
      def agile_color_class(issue, options = {})
        base = options[:color_base] || RedmineAgile.color_base
        if base == 'tracker' && RedmineAgile.use_colors?
          "taskman-tracker-card #{TrackerColors.css_class(issue.tracker)}"
        else
          super
        end
      end
    end

    # Let Redmine render all geometry, relationships and overlays unchanged.
    # Only add the tracker class to the HTML tags as the renderer creates them.
    class GanttView < SimpleDelegator
      def initialize(view, tracker)
        super(view)
        @tracker_class = TrackerColors.css_class(tracker)
      end

      def content_tag(name, content = nil, options = nil, escape = true, &block)
        if name == :div && options && options[:class].to_s.split.include?('task')
          options = options.merge(class: "#{options[:class]} #{@tracker_class}")
        end
        __getobj__.content_tag(name, content, options, escape, &block)
      end
    end

    module GanttColors
      private

      def html_task(params, coords, markers, label, object)
        return super unless object.is_a?(Issue) && object.tracker

        original_view = view
        self.view = GanttView.new(original_view, object.tracker)
        begin
          super
        ensure
          self.view = original_view
        end
      end
    end

    module CumulativeFlowColors
      def dataset(dataset_data, label, options = {})
        @taskman_trackers_by_name ||= begin
          scope = Tracker.all
          scope = scope.preload(:agile_color) if Tracker.reflect_on_association(:agile_color)
          scope.to_a.to_h { |tracker| [tracker.name, tracker] }
        end
        tracker = @taskman_trackers_by_name[label]
        options = options.merge(color: TrackerColors.rgb(TrackerColors.for_tracker(tracker)).join(',')) if tracker
        super(dataset_data, label, options)
      end
    end

    module CycleTimeColors
      private

      def bubbles_datasets
        datasets = super
        trackers = bubbles_data.keys.sort
        datasets.zip(trackers).map do |dataset, tracker|
          # The synthetic "mixed trackers" bubble has no tracker identity.
          tracker.id ? dataset.merge(backgroundColor: TrackerColors.for_tracker(tracker)) : dataset
        end
      end
    end

    def self.apply!
      Issue.prepend(IssueColors) unless Issue.ancestors.include?(IssueColors)
      if Tracker.reflect_on_association(:agile_color)
        Tracker.prepend(TrackerDefaults) unless Tracker.ancestors.include?(TrackerDefaults)
      end
      if defined?(AgileBoardsHelper)
        AgileBoardsHelper.prepend(BoardColors) unless AgileBoardsHelper.ancestors.include?(BoardColors)
      end
      gantt = Redmine::Helpers::Gantt
      gantt.prepend(GanttColors) unless gantt.ancestors.include?(GanttColors)
      if defined?(RedmineAgile::Charts::TrackersCumulativeFlowChart)
        chart = RedmineAgile::Charts::TrackersCumulativeFlowChart
        chart.prepend(CumulativeFlowColors) unless chart.ancestors.include?(CumulativeFlowColors)
      end
      if defined?(RedmineAgile::Charts::CycleTimeChart)
        chart = RedmineAgile::Charts::CycleTimeChart
        chart.prepend(CycleTimeColors) unless chart.ancestors.include?(CycleTimeColors)
      end
    end
  end
end

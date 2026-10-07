# frozen_string_literal: true

require_relative 'eea_patches/tracker_color_patches'
require_relative 'eea_patches/tracker_colors_hook'

module IssueTrackerColorPatch
  def self.apply!
    require_dependency 'issue'
    require_dependency 'tracker'
    require_dependency 'redmine/helpers/gantt'
    if Redmine::Plugin.installed?(:redmine_agile) && !defined?(AgileBoardsHelper)
      # Plugin helper directories need not be present on Ruby's $LOAD_PATH.
      agile_directory = Redmine::Plugin.find(:redmine_agile).directory
      require_dependency File.join(agile_directory, 'app', 'helpers', 'agile_boards_helper.rb')
    end
    EeaPatches::TrackerColorPatches.apply!
  end

  Rails.application.config.to_prepare { IssueTrackerColorPatch.apply! }
end

# frozen_string_literal: true

require_relative 'tracker_color_patches'
require_relative 'tracker_colors_hook'

Rails.application.config.to_prepare do
  require_dependency 'issue'
  require_dependency 'tracker'
  require_dependency 'redmine/helpers/gantt'
  require_dependency 'agile_boards_helper' if Redmine::Plugin.installed?(:redmine_agile)
  EeaPatches::TrackerColorPatches.apply!
end

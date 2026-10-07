require 'redmine'

Redmine::Plugin.register :zzzz_eea_patches do
  name 'EEA Performance Patches'
  author 'European Environment Agency (EEA)'
  description 'Performance optimizations and patches for Redmine plugins'
  version '1.3.0'
  url 'https://github.com/eea/eea.docker.redmine'
  author_url 'https://www.eea.europa.eu'

  requires_redmine version_or_higher: '5.0.0'
end

# Wire Rack::MiniProfiler authorization at plugin load time.
# Runs after Rails initialization but before first request,
# taking precedence over config/initializers/rack_mini_profiler.rb.
require_relative 'lib/eea_patches/mini_profiler_patch'
EeaPatches::MiniProfilerPatch.configure!

require_relative 'lib/eea_patches/mini_profiler_authorization_patch'
EeaPatches::MiniProfilerAuthorizationPatch.apply!

# Shared automatic tracker colors for A1, Gantt, lists and Agile.
require_relative 'lib/issue_tracker_color_patch'
# Plugin init itself runs inside Redmine's to_prepare callback. Install now,
# since a callback registered here may only run on a subsequent prepare cycle.
IssueTrackerColorPatch.apply!

Rails.logger.info '[zzzz_eea_patches] Plugin registered (view overrides + MiniProfiler authorization)'

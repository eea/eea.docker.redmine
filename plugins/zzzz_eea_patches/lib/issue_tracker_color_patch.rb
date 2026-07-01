# plugins/zzzz_eea_patches/lib/issue_tracker_color_patch.rb
#
# Adds a tracker-name-<parameterized> CSS class to issue links so the theme
# can render tracker-colored pills (e.g. Bug -> red, Feature -> blue).
#
# The core Issue#css_classes method already emits tracker-<id> (e.g. tracker-1),
# but database IDs are not stable across environments. This patch adds a
# name-based class (e.g. tracker-name-bug) that survives ID changes.

module IssueTrackerColorPatch
  def css_classes(user = User.current)
    s = super
    return s unless tracker
    s + " tracker-name-#{tracker.name.parameterize}"
  end
end

Rails.application.config.after_initialize do
  Issue.prepend(IssueTrackerColorPatch) unless Issue.ancestors.include?(IssueTrackerColorPatch)
end

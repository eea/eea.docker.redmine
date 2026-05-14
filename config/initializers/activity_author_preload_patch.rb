# frozen_string_literal: true

# Runtime patch: Activity Author Preload
# Fixes N+1 query problem in activity page rendering where event_author triggers
# individual queries even when author was preloaded in the scope.
#
# Root cause: acts_as_activity_provider's preload(:author) doesn't prevent
# per-event queries when event_author is called via the acts_as_event wrapper.
#
# Fix: After events are fetched, bulk preload all authors in one query.

require_relative '../lib/redmine/activity/fetcher'

module ActivityAuthorPreloadPatch
  def events(from = nil, to = nil, options = {})
    events = super

    # Only apply to HTML format (not Atom which uses limit)
    return events if options[:limit]

    # Group events by class and bulk preload authors
    events_by_class = events.group_by(&:class)

    events_by_class.each do |klass, class_events|
      # Check if this class has author association and uses acts_as_event
      next unless klass.respond_to?(:reflect_on_association)
      next unless klass.reflect_on_association(:author)
      next unless class_events.first.respond_to?(:event_author)

      # Bulk preload authors for all events of this class
      # This forces the association to be loaded in one query
      ActiveRecord::Associations::Preloader.new(
        records: class_events,
        associations: :author
      ).call
    end

    events
  end
end

# Prepend the patch to Activity::Fetcher
Redmine::Activity::Fetcher.prepend(ActivityAuthorPreloadPatch)

Rails.logger.info "[runtime_compat] patch=ACTIVITY_AUTHOR_PRELOAD enabled=true"

# Override SolidQueue::Configuration to support SOLID_QUEUE_ONLY_WORK env var.
# When set to "1", only workers start (no scheduler or dispatcher).
# This enables separating scheduler and workers into different K8s deployments.
#
# Usage:
#   - Worker deployment: SOLID_QUEUE_ONLY_WORK=1 + SOLID_QUEUE_SKIP_RECURRING=1
#   - Scheduler deployment: default (no env vars needed)

module SolidQueueOnlyWorkOverride
  def default_options
    super.merge(
      only_work: ActiveModel::Type::Boolean.new.cast(ENV["SOLID_QUEUE_ONLY_WORK"]),
      skip_recurring: ActiveModel::Type::Boolean.new.cast(ENV.fetch("SOLID_QUEUE_SKIP_RECURRING", "0"))
    )
  end
end

if defined?(SolidQueue::Configuration)
  SolidQueue::Configuration.prepend(SolidQueueOnlyWorkOverride)
end

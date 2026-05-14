# frozen_string_literal: true

# Archived (disabled) Taskman runtime_compat patches.
#
# IMPORTANT:
# - This file is intentionally placed under config/stale so Rails does NOT auto-load it.
# - Keep here only for reference/history.
# - To restore any patch, copy it back into config/initializers/runtime_compat.rb
#   and explicitly re-enable corresponding env toggle.
#
# Archive Metadata:
# - Disabled date: 2026-05-12
# - Disabled by: taskman maintainers
# - Reason summary:
#   - RESOURCE_BOOKING_SUM: slower in observed dataset
#   - DEALS_CONTROLLER_INTERSECTION: not helping for ticketing flows, extra complexity
#   - PROJECT_ENABLED_MODULES: stale-read risk lane
#
# Restore Checklist:
# 1) Copy patch block back to config/initializers/runtime_compat.rb
# 2) Ensure rescue/fallback pattern matches current standards
# 3) Re-add env toggle in helm values (if intentionally managed there)
# 4) Validate with production-like benchmark and correctness checks
# 5) Document reactivation rationale in docs/patches/PATCHES.md

# -----------------------------------------------------------------------------
# RESOURCE_BOOKING_SUM (disabled)
# -----------------------------------------------------------------------------
# Toggle: TASKMAN_PATCH_RESOURCE_BOOKING_SUM
resource_booking_sum_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('RESOURCE_BOOKING_SUM')
TaskmanRuntimeCompat.log_patch('RESOURCE_BOOKING_SUM', resource_booking_sum_patch_enabled)
Rails.application.config.to_prepare do
  next unless resource_booking_sum_patch_enabled
  next unless defined?(ResourceBooking)

  unless defined?(TaskmanResourceBookingSumPatch)
    module TaskmanResourceBookingSumPatch
      def total_hours_sum
        sum(:total_hours)
      rescue StandardError => e
        Rails.logger.warn("[ResourceBookingSumPatch] total_hours_sum fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  ResourceBooking.prepend(TaskmanResourceBookingSumPatch) unless ResourceBooking.ancestors.include?(TaskmanResourceBookingSumPatch)
end

# -----------------------------------------------------------------------------
# DEALS_CONTROLLER_INTERSECTION (disabled)
# -----------------------------------------------------------------------------
# Toggle: TASKMAN_PATCH_DEALS_CONTROLLER_INTERSECTION
deals_controller_intersection_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('DEALS_CONTROLLER_INTERSECTION')
TaskmanRuntimeCompat.log_patch('DEALS_CONTROLLER_INTERSECTION', deals_controller_intersection_patch_enabled)
Rails.application.config.to_prepare do
  next unless deals_controller_intersection_patch_enabled
  next unless defined?(DealsController)

  unless defined?(TaskmanDealsControllerIntersectionPatch)
    module TaskmanDealsControllerIntersectionPatch
      def index
        super
        if @projects && @projects.any?
          @available_statuses    = @projects.map(&:deal_statuses).reduce(:&) || []
          @available_categories  = @projects.map(&:deal_categories).reduce(:&) || []
          @assignables           = @projects.map(&:assignable_users).reduce(:&) || []
        end
      rescue StandardError => e
        Rails.logger.warn("[DealsControllerIntersectionPatch] index fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  DealsController.prepend(TaskmanDealsControllerIntersectionPatch) unless DealsController.ancestors.include?(TaskmanDealsControllerIntersectionPatch)
end

# -----------------------------------------------------------------------------
# PROJECT_ENABLED_MODULES (disabled)
# -----------------------------------------------------------------------------
# Toggle: TASKMAN_PATCH_PROJECT_ENABLED_MODULES
project_enabled_modules_patch_enabled = TaskmanRuntimeCompat.patch_enabled?('PROJECT_ENABLED_MODULES')
TaskmanRuntimeCompat.log_patch('PROJECT_ENABLED_MODULES', project_enabled_modules_patch_enabled)
Rails.application.config.to_prepare do
  next unless project_enabled_modules_patch_enabled
  next unless defined?(Project)

  unless defined?(TaskmanProjectEnabledModulesPatch)
    module TaskmanProjectEnabledModulesPatch
      def enabled_modules
        super
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.warn("[ProjectEnabledModulesPatch] enabled_modules fallback: #{e.class}: #{e.message}")
        super
      end
    end
  end

  Project.prepend(TaskmanProjectEnabledModulesPatch) unless Project.ancestors.include?(TaskmanProjectEnabledModulesPatch)
end

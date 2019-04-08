require 'projects_helper'

module Banners
    module ProjectsHelperPatch
      def self.included(base)
        base.send(:include, InstanceMethods)
        base.class_eval do
          unloadable
          alias_method :project_settings_tabs_without_banner, :project_settings_tabs
          alias_method :project_settings_tabs, :project_settings_tabs_with_banner
        end
      end

      module InstanceMethods
  	    extend ActiveSupport::Concern

        def project_settings_tabs_with_banner
          tabs = project_settings_tabs_without_banner
          @banner = Banner.find_or_create(@project.id)
          action = { name: 'banner',
                     controller: 'banner',
                     action: :show,
                     partial: 'banner/show', label: :banner }
          tabs << action if User.current.allowed_to?(action, @project)
          tabs
        end
      end
    end
end


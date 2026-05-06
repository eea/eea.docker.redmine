require 'redmine'

Redmine::Plugin.register :redmine_eea_patches do
  name 'EEA Performance Patches'
  author 'European Environment Agency (EEA)'
  description 'Performance optimizations and patches for Redmine plugins'
  version '1.0.0'
  url 'https://github.com/eea/eea.docker.redmine'
  author_url 'https://www.eea.europa.eu'

  # Minimum Redmine version
  requires_redmine version_or_higher: '5.0.0'

  # Must load AFTER redmine_contacts_helpdesk so view overrides take effect
  requires_redmine_plugin :redmine_contacts_helpdesk, :version_or_higher => '4.0.0'
end

# Log that the plugin is loaded
Rails.logger.info '[redmine_eea_patches] Plugin loaded successfully'

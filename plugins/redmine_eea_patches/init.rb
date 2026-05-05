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

  # NOTE: redmine_contacts_helpdesk is not required as a hard dependency
  # because this plugin only provides view overrides that gracefully skip
  # when HelpdeskTicket is not defined. The skip_unless defined?(HelpdeskTicket)
  # pattern in tests handles this.
end

# Log that the plugin is loaded
Rails.logger.info '[redmine_eea_patches] Plugin loaded successfully'

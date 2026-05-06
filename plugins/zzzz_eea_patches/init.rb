require 'redmine'

Redmine::Plugin.register :zzzz_eea_patches do
  name 'EEA Performance Patches'
  author 'European Environment Agency (EEA)'
  description 'Performance optimizations and patches for Redmine plugins'
  version '1.1.0'
  url 'https://github.com/eea/eea.docker.redmine'
  author_url 'https://www.eea.europa.eu'

  requires_redmine version_or_higher: '5.0.0'
  requires_redmine_plugin :redmine_contacts_helpdesk, :version_or_higher => '4.0.0'
end

Rails.logger.info '[zzzz_eea_patches] Plugin registered, dir=zzzz_eea_patches'

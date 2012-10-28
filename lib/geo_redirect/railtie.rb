require 'geo_redirect'
require 'rails'

module GeoRedirect
  class Railtie < Rails::Railtie
    rake_tasks do
      require 'tasks/geo_redirect.rb'
    end
  end
end

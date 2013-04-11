require 'geo_redirect/middleware'
require 'geo_redirect/version'

module GeoRedirect

  # Load rake tasks
  require 'geo_redirect/railtie' if defined?(Rails)

end

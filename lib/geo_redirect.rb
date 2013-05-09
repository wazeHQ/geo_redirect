require 'geo_redirect/middleware'
require 'geo_redirect/version'

module GeoRedirect

  # Load rake tasks
  if defined? Rails
    require 'geo_redirect/railtie'
  end

end

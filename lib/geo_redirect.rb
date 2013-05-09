require 'geo_redirect/middleware'
require 'geo_redirect/version'

module GeoRedirect
  DEFAULT_DB_PATH     = 'db/GeoIP.dat'
  DEFAULT_CONFIG_PATH = 'config/geo_redirect.yml'

  # Load rake tasks
  if defined? Rails
    require 'geo_redirect/railtie'
  end

end

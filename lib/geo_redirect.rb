require 'geo_redirect/middleware'
require 'geo_redirect/version'

module GeoRedirect
  DEFAULT_DB_PATH     = 'db/GeoIP.dat'.freeze
  DEFAULT_CONFIG_PATH = 'config/geo_redirect.yml'.freeze

  # Load rake tasks
  require 'geo_redirect/railtie' if defined? Rails
end

require 'yaml'
require 'geoip'
require 'geo_redirect/version'

module GeoRedirect
  # Load rake tasks
  require 'geo_redirect/railtie.rb' if defined?(Rails)

  # Rack middleware
  class Middleware
    def initialize(app, options = {})
      # Some defaults
      options[:db]     ||= 'db/GeoIP.dat'
      options[:config] ||= 'config/geo_redirect.yml'

      @app = app

      # Load GeoIP database
      begin
        @db = GeoIP.new(options[:db])
      rescue Errno::EINVAL, Errno::ENOENT => e
        puts "Could not load GeoIP database file."
        puts "Please make sure you have a valid one and"
        puts "add its name to the GeoRedirect middleware."
        puts "Alternatively, use `rake georedirect:fetch_db`"
        puts "to fetch it to the default location (under db/)."
        raise e
      end

      # Load config object
      begin
        @config = YAML.load_file('config/geo_redirect.yml')
        raise Errno::EINVAL unless @config
      rescue Errno::EINVAL, Errno::ENOENT => e
        puts "Could not load GeoRedirect config YML file."
        puts "Please make sure you have a valid YML file"
        puts "and pass its name when adding the"
        puts "GeoRedirect middlware."
        raise e
      end
    end

    def call(env)
      # Current request
      request = Rack::Request.new(env)

      #TODO check for session cookie
      #TODO handle ?redirect=1

      # Fetch country code
      country = nil
      begin
        res     = @db.country(env['REMOTE_ADDR'])
        code    = res.try(:country_code)
        country = res.try(:country_code2) unless code.nil? || code.zero?
      rescue
        country = nil
      end

      unless country.nil?
        # Desired host
        desired = host_by_country(country)

        # Compare with current host
        unless request.host.ends_with?(desired)
          # Wrong host, redirect
          url = URI.parse(request.url).tap { |u|
            u.host = desired
            u.port = nil # use default port at second host
          }
          return [301, {'Location' => url.to_s}, self]
        end
      end

      # Carry on
      @app.call(env)
    end

    protected
    def host_by_country(code)
      hosts    = @config[:countries].select { |k, o| o.include?(code) }
      host_key = hosts.try(:keys).try(:first)

      # Fallback to :default if no host found
      host_key = :default if (host_key.nil? || !@config[:hosts].key?(host_key))

      @config[:hosts][host_key]
    end
  end
end

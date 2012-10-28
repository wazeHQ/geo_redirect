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

      #TODO remove me
      @log = Logger.new('/tmp/geo.log')
    end

    def call(env)
      # Current request
      request = Rack::Request.new(env)
      url     = URI.parse(request.url)
      query   = CGI::parse(url.query || '')

      country = nil
      #TODO check for session cookie

      # Handle ?redirect=1 forcing
      if query.key?('redirect')
        remember_host(url.host)
        #TODO remove ?redirect=1 (by redirect)

      else
        # Fetch country code
        begin
          env['REMOTE_ADDR'] = '192.117.10.52'
          res     = @db.country(env['REMOTE_ADDR'])
          code    = res.try(:country_code)
          country = res.try(:country_code2) unless code.nil? || code.zero?
        rescue
          country = nil
        end
      end

      unless country.nil?
        # Desired host
        desired = host_by_country(country)
        remember_host(desired)

        return redirect_request(request, desired, env)
      end

      # Carry on
      @app.call(env)
    end

    protected
    def redirect_request(request, host, env)
      # Compare with current host
      unless request.host.ends_with?(host)
        # Wrong host, redirect
        url = URI.parse(request.url).tap { |u|
          u.host = host
          u.port = nil
        }
        [301, {'Location' => url.to_s}, self]
      else
        @app.call(env)
      end
    end

    def host_by_country(code)
      hosts    = @config[:countries].select { |k, o| o.include?(code) }
      host_key = hosts.try(:keys).try(:first)

      # Fallback to :default if no host found
      host_key = :default if (host_key.nil? || !@config[:hosts].key?(host_key))

      @config[:hosts][host_key]
    end

    def remember_host(host)
      @log.debug "-- supposed to remember #{host} --"
    end
  end
end

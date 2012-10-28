require 'yaml'
require 'geoip'
require 'geo_redirect/version'

module GeoRedirect
  # Load rake tasks
  require 'geo_redirect/railtie' if defined?(Rails)

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

      # check for session var
      @log.debug "session = #{request.session}"
      if request.session[:geo_redirect]
        host = request.session[:geo_redirect]
        @log.debug "!! remembered #{host} !!"
        if @config[host].present?
          return redirect_request(request, env, host)
        else
          # Invalid session var, remove it
          remember_host(request, nil)
        end
      end

      # Handle ?redirect=1 forcing
      if query.key?('redirect')
        host = host_by_hostname(url.host)
        remember_host(request, host)
        #TODO remove ?redirect=1 (by redirect)
        #     query.delete('redirect').to_param (sort-of)

      else
        # Fetch country code
        begin
          env['REMOTE_ADDR'] = '192.117.10.52' #TODO remove me
          res     = @db.country(env['REMOTE_ADDR'])
          code    = res.try(:country_code)
          country = res.try(:country_code2) unless code.nil? || code.zero?
        rescue
          country = nil
        end
      end

      unless country.nil?
        host = host_by_country(country) # desired host
        remember_host(request, host)

        return redirect_request(request, env, host)
      end

      # Carry on
      @app.call(env)
    end

    protected
    def redirect_request(request, env, host=nil)
      if @config[host].present? # Valid host key
        # Compare with current host
        unless request.host.ends_with?(host)
          url = URI.parse(request.url).tap
          url.port = nil
          url.host = @config[host][:host] if host

          @log.debug "~~ supposed to redirect to #{url} ~~"
          return [301, {'Location' => url.to_s}, self]
        end
      end

      # otherwise, carry on
      @app.call(env)
    end

    def host_by_country(country)
      hosts = @config.select { |k, v| Array(v[:countries]).include?(country) }
      hosts.keys.first || :default
    end

    def host_by_hostname(hostname)
      hosts = @config.select { |k, v| v[:host] == hostname }
      hosts.keys.first || :default
    end

    def remember_host(request, host)
      @log.debug "-- supposed to remember #{host} --"
      request.session[:geo_redirect] = host
    end
  end
end

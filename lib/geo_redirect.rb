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
    end

    def call(env)
      @request = Rack::Request.new(env)

      if force_redirect?
        handle_force

      elsif session_exists?
        handle_session

      else
        handle_geoip
      end
    end

    def session_exists?
      host = @request.session['geo_redirect']
      if host.present? && @config[host].nil? # Invalid var, remove it
        forget_host
        host = nil
      end

      host.present?
    end

    def handle_session
      host = @request.session['geo_redirect']
      redirect_request(host)
    end

    def force_redirect?
      url = URI.parse(@request.url)
      Rack::Utils.parse_query(url.query).key? 'redirect'
    end

    def handle_force
      url = URI.parse(@request.url)
      host = host_by_hostname(url.host)
      remember_host(host)
      redirect_request(url.host, true)
    end

    def handle_geoip
      # Fetch country code
      begin
        res     = @db.country(@request.env['REMOTE_ADDR'])
        code    = res.try(:country_code)
        country = res.try(:country_code2) unless code.nil? || code.zero?
      rescue
        country = nil
      end

      unless country.nil?
        host = host_by_country(country) # desired host
        remember_host(host)

        redirect_request(host)
      else
        @app.call(@request.env)
      end
    end

    def redirect_request(host=nil, same_host=false)
      redirect = true
      unless host.nil?
        hostname = host.is_a?(Symbol) ? @config[host][:host] : host
        redirect = hostname.present?
        redirect &&= !@request.host.ends_with?(hostname) unless same_host
      end

      if redirect
        url = URI.parse(@request.url)
        url.port = nil
        url.host = hostname if host
        # Remove 'redirect' GET arg
        url.query = Rack::Utils.parse_query(url.query).tap{ |u|
          u.delete('redirect')
        }.to_param
        url.query = nil if url.query.empty?

        [301, {'Location' => url.to_s, 'Content-Type' => ''}, ['Moved Permanently\n']]
      else
        @app.call(@request.env)
      end
    end

    def host_by_country(country)
      hosts = @config.select { |k, v| Array(v[:countries]).include?(country) }
      hosts.keys.first || :default
    end

    def host_by_hostname(hostname)
      hosts = @config.select { |k, v| v[:host] == hostname }
      hosts.keys.first || :default
    end

    def remember_host(host)
      @request.session['geo_redirect'] = host
    end

    def forget_host
      remember_host(nil)
    end
  end
end

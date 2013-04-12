require 'yaml'
require 'geoip'

module GeoRedirect
  DEFAULT_DB_PATH     = 'db/GeoIP.dat'
  DEFAULT_CONFIG_PATH = 'config/geo_redirect.yml'

  class Middleware
    attr_accessor :db, :config

    def initialize(app, options = {})
      # Some defaults
      options[:db]     ||= DEFAULT_DB_PATH
      options[:config] ||= DEFAULT_CONFIG_PATH
      @logfile = options[:logfile] || nil

      @app = app

      @db     = load_db(options[:db])
      @config = load_config(options[:config])

      self.log "Initialized middleware"
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
      if host && @config[host].nil? # Invalid var, remove it
        self.log "Invalid session var, forgetting"
        forget_host(host)
        host = nil
      end

      !host.nil?
    end

    def handle_session
      host = @request.session['geo_redirect']
      self.log "Handling session var: #{host}"
      redirect_request(host)
    end

    def force_redirect?
      url = URI.parse(@request.url)
      Rack::Utils.parse_query(url.query).key? 'redirect'
    end

    def handle_force
      url = URI.parse(@request.url)
      host = host_by_hostname(url.host)
      self.log "Handling force flag: #{host}"
      remember_host(host)
      redirect_request(url.host, true)
    end

    def handle_geoip
      country = country_from_request rescue nil
      self.log "GeoIP match: country code #{country}"

      unless country.nil?
        host = host_by_country(country) # desired host
        self.log "GeoIP host match: #{host}"
        remember_host(host)

        redirect_request(host)
      else
        @app.call(@request.env)
      end
    end

    def redirect_request(host=nil, same_host=false)
      hostname = hostname_by_host(host)

      if should_redirect?(hostname, same_host)
        url = redirect_url(hostname)

        self.log "Redirecting to #{url}"
        [301,
         {'Location' => url.to_s, 'Content-Type' => 'text/plain'},
         ['Moved Permanently\n']]
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

    def hostname_by_host(host)
      host.is_a?(Symbol) ? @config[host][:host] : host
    end

    def remember_host(host)
      self.log "Remembering: #{host}"
      @request.session['geo_redirect'] = host
    end

    def forget_host(host)
      self.log "Forgetting: #{host}"
      remember_host(nil)
    end

    protected
    def log(message)
      unless @logfile.nil?
        @logger ||= Logger.new(@logfile)
        @logger.debug("[GeoRedirect] #{message}")
      end
    end

    def load_db(path)
      begin
        GeoIP.new(path)
      rescue Errno::EINVAL, Errno::ENOENT => e
        puts "Could not load GeoIP database file."
        puts "Please make sure you have a valid one and"
        puts "add its name to the GeoRedirect middleware."
        puts "Alternatively, use `rake georedirect:fetch_db`"
        puts "to fetch it to the default location (under db/)."
        raise e
      end
    end

    def load_config(path)
      begin
        (YAML.load_file(path)) || (raise Errno::EINVAL)
      rescue Errno::EINVAL, Errno::ENOENT => e
        puts "Could not load GeoRedirect config YML file."
        puts "Please make sure you have a valid YML file"
        puts "and pass its name when adding the"
        puts "GeoRedirect middlware."
        raise e
      end
    end

    def request_ip
      ip_address = @request.env['HTTP_X_FORWARDED_FOR'] || @request.env['REMOTE_ADDR']
      # take only the first given ip
      ip_address.split(',').first.strip
    end


    def country_from_request
      ip = request_ip
      self.log "Handling GeoIP lookup: IP #{ip}"

      res     = @db.country(ip)
      code    = res[:country_code]

      res[:country_code2] unless code.nil? || code.zero?
    end

    def redirect_url(hostname)
      url = URI.parse(@request.url)
      url.port = nil
      url.host = hostname if hostname

      # Remove force flag from GET arguments
      query_hash = Rack::Utils.parse_query(url.query).tap{ |u|
        u.delete('redirect')
      }

      # Copy query
      url.query = URI.encode_www_form(query_hash)
      url.query = nil if url.query.empty?

      url
    end

    def should_redirect?(hostname, same_host)
      unless hostname.nil? || same_host
        hostname_ends_with = %r{#{hostname.gsub(".", "\.")}$}
        (@request.host =~ hostname_ends_with).nil?
      else
        true
      end
    end

  end
end

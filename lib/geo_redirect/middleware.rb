require 'yaml'
require 'geoip'

module GeoRedirect
  class Middleware
    attr_accessor :db, :config

    def initialize(app, options = {})
      # Some defaults
      options[:db] ||= DEFAULT_DB_PATH
      options[:config] ||= DEFAULT_CONFIG_PATH

      @app = app

      @logger   = init_logger(options[:logfile]) if options[:logfile]
      @db       = init_db(options[:db])
      @config   = init_config(options[:config])
      @excludes = Array(options[:exclude])

      log 'Initialized middleware'
    end

    def call(env)
      @request = Rack::Request.new(env)

      if skip_redirect?
        @app.call(env)

      elsif force_redirect?
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
        log 'Invalid session var, forgetting'
        forget_host(host)
        host = nil
      end

      !host.nil?
    end

    def handle_session
      host = @request.session['geo_redirect']
      log "Handling session var: #{host}"
      redirect_request(host)
    end

    def force_redirect?
      url = URI.parse(@request.url)
      Rack::Utils.parse_query(url.query).key? 'redirect'
    end

    def skip_redirect?
      url = URI.parse(@request.url)
      query_includes_skip_geo?(url) || path_excluded?(url)
    end

    def query_includes_skip_geo?(url)
      Rack::Utils.parse_query(url.query).key? 'skip_geo'
    end

    def path_excluded?(url)
      @excludes.any? { |exclude| url.path == exclude }
    end

    def handle_force
      url = URI.parse(@request.url)
      host = host_by_hostname(url.host)
      log "Handling force flag: #{host}"
      remember_host(host)
      redirect_request(url.host, true)
    end

    def handle_geoip
      country = country_from_request rescue nil
      @request.session['geo_redirect.country'] = country
      log "GeoIP match: country code #{country}"

      if country.nil?
        @app.call(@request.env)
      else
        host = host_by_country(country) # desired host
        log "GeoIP host match: #{host}"
        remember_host(host)

        redirect_request(host)
      end
    end

    def redirect_request(host = nil, same_host = false)
      hostname = hostname_by_host(host)

      if should_redirect?(hostname, same_host)
        url = redirect_url(hostname)

        log "Redirecting to #{url}"
        [301,
         { 'Location' => url.to_s, 'Content-Type' => 'text/plain' },
         ['Moved Permanently\n']]
      else
        @app.call(@request.env)
      end
    end

    def host_by_country(country)
      hosts = @config.select { |_k, v| Array(v[:countries]).include?(country) }
      hosts.keys.first || :default
    end

    def host_by_hostname(hostname)
      hosts = @config.select { |_k, v| v[:host] == hostname }
      hosts.keys.first || :default
    end

    def hostname_by_host(host)
      host.is_a?(Symbol) ? @config[host][:host] : host
    end

    def remember_host(host)
      log "Remembering: #{host}"
      @request.session['geo_redirect'] = host
    end

    def forget_host(host)
      log "Forgetting: #{host}"
      remember_host(nil)
    end

    protected

    def log(message, level = :debug)
      @logger.send(level, "[GeoRedirect] #{message}") unless @logger.nil?
    end

    def init_logger(path)
      Logger.new(path)
    rescue Errno::EINVAL, Errno::EACCES
      nil
    end

    def init_db(path)
      GeoIP.new(path)
    rescue Errno::EINVAL, Errno::ENOENT
      message = <<-ERROR
        Could not load GeoIP database file.
        Please make sure you have a valid one and add its name to
        the GeoRedirect middleware.
        Alternatively, use `rake georedirect:fetch_db` to fetch it
        to the default location (under db/).
      ERROR
      log(message, :error)
    end

    def init_config(path)
      YAML.load_file(path) || fail(Errno::EINVAL)
    rescue Errno::EINVAL, Errno::ENOENT, Psych::SyntaxError, SyntaxError
      message = <<-ERROR
        Could not load GeoRedirect config YML file.
        Please make sure you have a valid YML file and pass its name
        when adding the GeoRedirect middlware.
      ERROR
      log(message, :error)
    end

    def request_ip
      ip_address =
        @request.env['HTTP_X_FORWARDED_FOR'] || @request.env['REMOTE_ADDR']
      # take only the first given ip
      ip_address.split(',').first.strip
    end

    def country_from_request
      ip = request_ip
      log "Handling GeoIP lookup: IP #{ip}"

      country = @db.country(ip)
      code = country[:country_code]

      country[:country_code2] unless code.nil? || code.zero?
    end

    def redirect_url(hostname)
      url = URI.parse(@request.url)
      url.port = nil
      url.host = hostname if hostname

      # Remove force flag from GET arguments
      query_hash = Rack::Utils.parse_query(url.query).tap do |u|
        u.delete('redirect')
      end

      # Copy query
      url.query = URI.encode_www_form(query_hash)
      url.query = nil if url.query.empty?

      url
    end

    def should_redirect?(hostname, same_host)
      return true if hostname.nil? || same_host

      hostname_ends_with = %r{#{hostname.tr('.', '\.')}$}
      (@request.host =~ hostname_ends_with).nil?
    end
  end
end

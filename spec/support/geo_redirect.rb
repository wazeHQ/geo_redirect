module GeoRedirect
  module Support
    def fixture_path(file)
      "spec/fixtures/#{file}"
    end

    def nonexisting_file_path
      '/no_such_file'
    end

    def app
      Rack::Lint.new(@app)
    end

    def mock_app(options = {})
      # Simple HTTP server that always returns 'Hello world!'
      main_app = lambda do |env|
        Rack::Request.new(env)
        headers = { 'Content-Type' => 'text/html' }
        [200, headers, ['Hello world!']]
      end

      @logfile = Tempfile.new('log')
      options = { config: fixture_path('config.yml'),
                  db: fixture_path('GeoIP.dat'),
                  logfile: @logfile.path
                }.merge(options)

      builder = Rack::Builder.new
      builder.use GeoRedirect::Middleware, options
      builder.run main_app
      @app = builder.to_app
    end

    def log_should_include(message)
      @logfile.rewind
      @logfile.read.should include(message)
    end
  end
end

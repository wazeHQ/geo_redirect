module GeoRedirect
  module Support
    def fixture_path(file)
      "spec/fixtures/#{file}"
    end

    def nonexisting_file_path
      "/no_such_file"
    end

    def app
      Rack::Lint.new(@app)
    end

    def mock_app(options = {})
      options = { :config => fixture_path("config.yml"),
                  :db => fixture_path("GeoIP.dat")
                }.merge(options)

      # Simple HTTP server that always returns 'Hello world!'
      main_app = lambda { |env|
        Rack::Request.new(env)
        headers = {"Content-Type" => "text/html"}
        [200, headers, ["Hello world!"]]
      }

      builder = Rack::Builder.new
      builder.use GeoRedirect::Middleware, options
      builder.run main_app
      @app = builder.to_app
    end
  end
end


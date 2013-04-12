require "rack"
require "logger"
require "tempfile"
require_relative "../lib/geo_redirect.rb"

# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  config.order = "random"
end

module GeoRedirect
  module Support
    def fixture_path(file)
      "spec/fixtures/#{file}"
    end

    def app; Rack::Lint.new(@app); end

    def mock_app(options = {})
      options = { :config => fixture_path("config.yml"),
                  :db => fixture_path("GeoIP.dat")
                }.merge(options)

      main_app = lambda { |env|
        Rack::Request.new(env)
        headers = {"Content-Type" => "text/html"}
        headers["Set-Cookie"] = "id=1; path=/\ntoken=abc; path=/; secure; HttpOnly"
        [200, headers, ["Hello world!"]]
      }

      builder = Rack::Builder.new
      builder.use GeoRedirect::Middleware, options
      builder.run main_app
      @app = builder.to_app
    end
  end
end

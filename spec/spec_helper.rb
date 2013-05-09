require "simplecov"
SimpleCov.start

require "rspec"
require "rack"
require "rack/test"

current_dir = File.dirname(__FILE__)
$LOAD_PATH.unshift(File.join(current_dir, '..', 'lib'))
$LOAD_PATH.unshift(current_dir)
require "geo_redirect"

Dir[File.join(current_dir, "support/**/*.rb")].each { |f| require f }

# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  config.order = "random"
end

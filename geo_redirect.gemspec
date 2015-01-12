# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'geo_redirect/version'

Gem::Specification.new do |gem|
  gem.name          = 'geo_redirect'
  gem.version       = GeoRedirect::VERSION
  gem.authors       = ['Sagie Maoz']
  gem.email         = ['sagie@waze.com']
  gem.description   = 'Geo-location based redirector'
  gem.summary       = 'Rack middleware to redirect clients to hostnames based on geo-location'
  gem.homepage      = ''

  gem.add_dependency 'rake'
  gem.add_dependency 'geoip'

  gem.add_development_dependency 'rspec',     '~> 3.1.0'
  gem.add_development_dependency 'rack',      '~> 1.6.0'
  gem.add_development_dependency 'rack-test', '~> 0.6.3'
  gem.add_development_dependency 'simplecov', '~> 0.9.1'

  gem.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  gem.executables   = gem.files.grep(%r{^bin/}).map { |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']
end

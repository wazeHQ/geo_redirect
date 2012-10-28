# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'geo_redirect/version'

Gem::Specification.new do |gem|
  gem.name          = "geo_redirect"
  gem.version       = GeoRedirect::VERSION
  gem.authors       = ["Sagie Maoz"]
  gem.email         = ["sagie@waze.com"]
  gem.description   = %q{Geo-location based redirector}
  gem.summary       = %q{Redirects users to hosts based on geolocation.}
  gem.homepage      = ""

  gem.add_dependency "geoip"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
end

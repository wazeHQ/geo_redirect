# Waze GeoRedirect
[![Build Status](https://secure.travis-ci.org/wazeHQ/geo_redirect.png)](http://travis-ci.org/wazeHQ/geo_redirect) [![Code Climate](https://codeclimate.com/github/wazeHQ/geo_redirect.png)](https://codeclimate.com/github/wazeHQ/geo_redirect) [![Gem Version](https://badge.fury.io/rb/geo_redirect.png)](http://badge.fury.io/rb/geo_redirect)

`GeoRedirect` is a Rack middleware that can be configured to
redirect incoming clients to different hosts based on their
geo-location data.

For instance, we use it for [our advertisers site](http://biz.waze.com/)
to redirect users to:

* [biz.waze.co.il](http://biz.waze.co.il) for Israel-incoming traffic.
* [biz.waze.com](http://biz.waze.com) for US and Canada incoming traffic.
* [biz-world.waze.com](http://biz-world.waze.com/) for any other sources.

The server stores a session variable with the server it decided on, for future traffic from the same client.

In addition, you can override these redirects by adding `?redirect=1` to any URL, and by that forcing the server to host from the current domain (and saving that domain to the user's session variable).

## Installation

Add this line to your application's Gemfile:

    gem 'geo_redirect'

And then execute:

    $ bundle


## Usage

These usage instructions were written for Rails products, although I'm pretty sure you could use the gem with any other Rack-based solution.

You'll need to add this to your `production.rb`:

	  Rails.application.middleware.use GeoRedirect::Middleware

This will make sure `GeoRedirect` runs before your application gets rolling.

The middleware requires two additional files to be present:

### 1. Configuration YML

This should be a YML file representing your redirection rules.

Here's a template that we use for the setup described above:

```
:us:
  :host: 'biz.waze.com'
  :countries: ['US', 'CA']

:il:
  :host: 'biz.waze.co.il'
  :countries: ['IL']

:world: &default
  :host: 'biz-world.waze.com'

:default: *default
```

Note that:

1. Every main item is a location, and must have a `host` configured.
2. A location can have a `countries` array. This will cause a redirect to this location for users from that country code. For available country codes, see [ISO 3166 Country Codes list](http://www.maxmind.com/en/iso3166) from MaxMind (the Geo IP provider `GeoRedirect` uses).
3. There must be a `default` location that would be used in case the client can't be geo-located.

### 2. GeoIP Countries database

`GeoRedirect` uses the [`geoip`](http://geoip.rubyforge.org/) gem for its geo-location functionality. In particular, it requires the `GeoLite country` free database from [MaxMind](http://www.maxmind.com/).

You can download the database file [directly from MaxMind](http://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz) and unzip it into `db/` in your project, **or** you could use the following `rake` task designed just for that:

	$ rake geo_redirect:fetch_db

It'd be a good idea to use this task on your (Capistrano or whatever) deployment scripts.

### Custom paths

The default paths for these files are:

1. `config/georedirect.yml`
2. `db/GeoIP.dat`

If that doesn't suit you, you can customize these when adding `GeoRedirect` to your project:

	  Rails.application.middleware.use GeoRedirect::Middleware, {
	  	:db => 'db/geo_database.dat',
	  	:config => 'geo_cfg.yml'
	  }

### Debugging

You can add a `logfile` path string when adding the middleware if you want it to log some of its decision process into the file.  
This is useful when working on your configuration YAML.

	Rails.application.middleware.use GeoRedirect::Middleware, :logfile => 'log/geo_redirect.log'

`GeoRedirect`'s log messages will always be prefixed with `[GeoRedirect]`.

### Accessing discovered country

The country code discovered for the current user is available for your convenience, under `session['geo_redirect.country']`.  
You can use it to make content decisions, or whatever.

## Known Issues

A couple issues I know about but haven't had the time to fix:

1. Cross-domain session var is required. In particular, if your stubborn user goes to more than 1 server with `?redirect=1`, all of these servers will never redirect them again (until the session is expired).
2. When a client accesses your site from an unknown hostname (one that was not configured in the `yml` file) with `?redirect=1`, they will stay in that hostname for the current session, but in the future would be redirected to the configured default hostname (because it was saved on their session var).


## Contributing

1. Fork it!
2. Create your feature branch! (`git checkout -b my-new-feature`)
3. Commit your changes! (`git commit -am 'Add some feature'`)
4. Push to the branch! (`git push origin my-new-feature`)
5. Create new Pull Request!

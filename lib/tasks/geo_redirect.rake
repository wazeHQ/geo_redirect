require 'geo_redirect'
require 'open-uri'
require 'zlib'

namespace :geo_redirect do
  DB_URI = 'http://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz'

  desc 'Fetches an updated copy of the GeoIP countries DB from MaxMind'
  task :fetch_db, :db_path do |_t, args|
    args.with_defaults(db_path: GeoRedirect::DEFAULT_DB_PATH)

    # Fetches DB copy and gunzips it
    # Thx http://stackoverflow.com/a/2014317/107085
    source = open(DB_URI)
    gz = Zlib::GzipReader.new(source)
    result = gz.read

    # Write to file
    File.open(args[:db_path], 'w') { |f| f.write(result) }
  end
end

require 'spec_helper'

describe 'geo_redirect:fetch_db' do
  include_context 'rake'

  it 'downloads a GeoIP db to a location' do
    dbfile = Tempfile.new('db')
    task.invoke(dbfile.path)
    expect(dbfile.size).to be > 0
  end
end

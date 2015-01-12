require 'spec_helper'
require 'tempfile'
require 'logger'

describe 'geo_redirect' do
  include GeoRedirect::Support
  include Rack::Test::Methods

  def session
    last_request.env['rack.session'] || {}
  end

  def url_scheme
    last_request.env['rack.url_scheme']
  end

  let(:config) { YAML.load_file(fixture_path('config.yml')) }

  describe '#load_config' do
    it 'reads a config file' do
      mock_app
      expect(@app.config).to eq(config)
    end

    it 'errors on not-found config file' do
      mock_app config: nonexisting_file_path
      log_should_include('ERROR')
      log_should_include('Could not load GeoRedirect config YML file')
    end

    it 'errors on a mal-formatted config file' do
      mock_app config: fixture_path('config.bad.yml')
      log_should_include('ERROR')
      log_should_include('Could not load GeoRedirect config YML file')
    end
  end

  describe '#load_db' do
    it 'reads a db file' do
      mock_app
      expect(@app.db).to be_a(GeoIP)
    end

    it 'errors on not-found db file' do
      mock_app db: nonexisting_file_path
      log_should_include('ERROR')
      log_should_include('Could not load GeoIP database file.')
    end

    # this example is disabled, as it seems that
    # GeoIP does not let me know if a db file is proper.
    #     it "errors on mal-formatted db file" do
    #       pending "GeoIP does not raise on bad files"
    #       mock_app :db => fixture_path("config.yml")
    #       log_should_include("ERROR")
    #       log_should_include("Could not load GeoIP database file.")
    #     end
  end

  describe '#log' do
    describe 'with valid logfile path' do
      before { mock_app }

      it 'initiates a log file' do
        @app.instance_variable_get(:"@logger").should be_kind_of Logger
      end

      it 'prints to log file' do
        message = 'Testing GeoRedirect logger'
        @app.send(:log, [message])
        log_should_include(message)
      end
    end

    it 'ignores invalid logfile path' do
      mock_app logfile: '/no_such_file'
      expect(@app.instance_variable_get(:"@logger")).to be_nil
    end
  end

  describe '#host_by_country' do
    before { mock_app }
    subject { @app.host_by_country(country) }

    context 'when country is valid' do
      let(:country) { 'US' }
      it { is_expected.to eq(:us) }
    end

    context 'when country is invalid' do
      let(:country) { 'WHATEVER' }
      it { is_expected.to eq(:default) }
    end
  end

  describe 'host_by_hostname' do
    before { mock_app }
    subject { @app.host_by_hostname(hostname) }

    context 'when hostname is valid' do
      let(:hostname) { 'biz.waze.co.il' }
      it { is_expected.to eq(:il) }
    end

    context 'when hostname is invalid' do
      let(:hostname) { 'something.else.org' }
      it { is_expected.to eq(:default) }
    end
  end

  describe 'redirect logic' do
    before :each do
      mock_app
    end

    def mock_request_from(code, options = {})
      ip = '5.5.5.5'

      if code.nil?
        country = nil
      else
        country = GeoIP::Country.stub(country_code2: code,
                                      country_code: 5)
      end
      @app.db.stub(:country).with(ip).and_return(country)

      env = { 'REMOTE_ADDR' => ip, 'HTTP_HOST' => 'biz.waze.co.il' }

      if options[:session]
        env['rack.session'] ||= {}
        env['rack.session']['geo_redirect'] = options[:session]
        env['rack.session']['geo_redirect.country'] = code
      end

      args = {}
      args[:redirect] = 1 if options[:force]
      args[:skip_geo] = true if options[:skip]

      get '/', args, env
    end

    def should_redirect_to(host)
      last_response.body.should include('Moved Permanently')
      last_response.status.should eq(301)
      last_response.headers.should have_key('Location')
      url = "#{url_scheme}://#{config[host][:host]}"
      last_response.headers['Location'].should start_with(url)
    end

    def should_not_redirect
      last_response.body.should include('Hello world!')
      last_response.should be_ok
    end

    def should_remember(host)
      session['geo_redirect'].should eq(host)
    end

    def should_remember_country(country)
      session['geo_redirect.country'].should eq(country)
    end

    describe 'without session memory' do
      describe 'for a foreign source' do
        before { mock_request_from 'US' }
        it { should_redirect_to :us }
        it { should_remember :us }
        it { should_remember_country 'US' }
      end

      describe 'for a local source' do
        before { mock_request_from 'IL' }
        it { should_not_redirect }
        it { should_remember :il }
        it { should_remember_country 'IL' }
      end

      describe 'for an unknown source' do
        before { mock_request_from 'SOMEWHERE OVER THE RAINBOW' }
        it { should_redirect_to :default }
        it { should_remember :default }
        it { should_remember_country 'SOMEWHERE OVER THE RAINBOW' }
      end
    end

    describe 'with valid session memory' do
      before { mock_request_from 'US', session: :default }
      it { should_redirect_to :default }
      it { should_remember :default }
      it { should_remember_country 'US' }
    end

    describe 'with invalid session memory' do
      before { mock_request_from 'US', session: 'foo' }

      it 'removes invalid session data' do
        expect(session['geo_redirect']).not_to eq('foo')
      end

      it { should_redirect_to :us }
      it { should_remember :us }
      it { should_remember_country 'US' }
    end

    describe 'with forced redirect flag' do
      before { mock_request_from 'US', force: true }

      it { should_redirect_to :il }
      it 'rewrites the flag out' do
        expect(last_response.headers['Location']).not_to include('redirect=1')
      end

      it { should_remember :il }
      it { should_remember_country nil }
    end

    describe 'with skip flag' do
      before { mock_request_from 'US', skip: true }
      it { should_not_redirect }
      it { should_remember nil }
      it { should_remember_country nil }
    end

    describe 'with no recognizable IP' do
      before { mock_request_from nil }
      it { should_not_redirect }
      it { should_remember nil }
      it { should_remember_country nil }
    end
  end
end

describe 'geo_redirect:fetch_db' do
  include_context 'rake'

  it 'downloads a GeoIP db to a location' do
    dbfile = Tempfile.new('db')
    subject.invoke(dbfile.path)
    expect(dbfile.size).to be > 0
  end
end

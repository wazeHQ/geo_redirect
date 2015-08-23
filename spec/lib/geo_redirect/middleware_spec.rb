require 'spec_helper'
require 'tempfile'
require 'logger'

describe GeoRedirect::Middleware do
  include GeoRedirect::Support
  include Rack::Test::Methods

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
        expect(@app.instance_variable_get(:"@logger")).to be_kind_of Logger
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
    let(:app_options) { {} }
    let(:request_ip) { '5.5.5.5' }
    let(:request_path) { '/' }
    let(:request_args) { {} }
    let(:request_session) { nil }
    let(:country) { { country_code: 5, country_code2: country_code } }
    let(:env) do
      {
        'REMOTE_ADDR' => request_ip,
        'HTTP_HOST' => 'biz.waze.co.il',
        'rack.session' => {
          'geo_redirect' => request_session,
          'geo_redirect.country' => (country_code if request_session)
        }
      }
    end

    before do
      mock_app(app_options)
      allow(@app.db).to receive(:country).with(request_ip).and_return(country)
      get request_path, request_args, env
    end

    subject(:session) { last_request.env['rack.session'] }
    subject { last_response }

    matcher :redirect_to do |expected|
      match do |response|
        url_scheme = last_request.env['rack.url_scheme']
        url = "#{url_scheme}://#{config[expected][:host]}"

        response.body.include?('Moved Permanently') &&
          response.status == 301 &&
          response.headers['Location'].start_with?(url)
      end
    end

    matcher :not_redirect do
      match do |response|
        response.body.include?('Hello world!') &&
          response.ok?
      end
    end

    matcher :remember do |host|
      match do
        session && session['geo_redirect'] == host
      end
    end

    matcher :remember_country do |country|
      match do
        session && session['geo_redirect.country'] == country
      end
    end

    describe 'without session memory' do
      describe 'for a foreign source' do
        let(:country_code) { 'US' }
        it { is_expected.to redirect_to :us }
        it { is_expected.to remember :us }
        it { is_expected.to remember_country 'US' }
      end

      describe 'for a local source' do
        let(:country_code) { 'IL' }
        it { is_expected.to not_redirect }
        it { is_expected.to remember :il }
        it { is_expected.to remember_country 'IL' }
      end

      describe 'for an unknown source' do
        let(:country_code) { 'SOMEWHERE OVER THE RAINBOW' }
        it { is_expected.to redirect_to :default }
        it { is_expected.to remember :default }
        it { is_expected.to remember_country 'SOMEWHERE OVER THE RAINBOW' }
      end
    end

    describe 'with valid session memory' do
      let(:request_session) { :default }
      let(:country_code) { 'US' }
      it { is_expected.to redirect_to :default }
      it { is_expected.to remember :default }
      it { is_expected.to remember_country 'US' }
    end

    describe 'with invalid session memory' do
      let(:request_session) { 'foo' }
      let(:country_code) { 'US' }

      it 'removes invalid session data' do
        expect(session['geo_redirect']).not_to eq('foo')
      end

      it { is_expected.to redirect_to :us }
      it { is_expected.to remember :us }
      it { is_expected.to remember_country 'US' }
    end

    describe 'with forced redirect flag' do
      let(:country_code) { 'US' }
      let(:request_args) { { redirect: 1 } }

      it { is_expected.to redirect_to :il }
      it 'rewrites the flag out' do
        expect(subject.headers['Location']).not_to include('redirect=1')
      end

      it { is_expected.to remember :il }
      it { is_expected.to remember_country nil }
    end

    describe 'with skip flag' do
      let(:country_code) { 'US' }
      let(:request_args) { { skip_geo: true } }
      it { is_expected.to not_redirect }
      it { is_expected.to remember nil }
      it { is_expected.to remember_country nil }
    end

    describe 'with no recognizable IP' do
      let(:country_code) { nil }
      it { is_expected.to not_redirect }
      it { is_expected.to remember nil }
      it { is_expected.to remember_country nil }
    end

    describe 'with an exclude option set' do
      let(:app_options) { { exclude: ['/exclude_me', '/exclude_me/too'] } }

      context 'when the request URL matches one of the excluded paths' do
        let(:country_code) { 'US' }
        let(:request_path) { '/exclude_me?query_param=value' }

        it { is_expected.to not_redirect }
        it { is_expected.to remember nil }
        it { is_expected.to remember_country nil }
      end

      context 'when the request URL does not match one of the excluded paths' do
        let(:country_code) { 'US' }
        let(:request_path) { '/dont_exclude_me?query_param=value' }

        it { is_expected.to redirect_to :us }
        it { is_expected.to remember :us }
        it { is_expected.to remember_country 'US' }
      end
    end

    describe 'with a single excluded path' do
      let(:app_options) { { exclude: '/exclude_me' } }

      context 'when the request URL matches one of the excluded paths' do
        let(:country_code) { 'US' }
        let(:request_path) { '/exclude_me?query_param=value' }

        it { is_expected.to not_redirect }
        it { is_expected.to remember nil }
        it { is_expected.to remember_country nil }
      end
    end
  end
end

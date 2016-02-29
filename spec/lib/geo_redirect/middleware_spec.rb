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
    context 'with valid logfile path' do
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

    it 'ignores empty logfile option' do
      mock_app logfile: nil
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

    context 'without session memory' do
      context 'for a foreign source' do
        let(:country_code) { 'US' }
        it { is_expected.to redirect_to :us }
        it { is_expected.to remember :us }
        it { is_expected.to remember_country 'US' }
      end

      context 'for a local source' do
        let(:country_code) { 'IL' }
        it { is_expected.to not_redirect }
        it { is_expected.to remember :il }
        it { is_expected.to remember_country 'IL' }
      end

      context 'for an unknown source' do
        let(:country_code) { 'SOMEWHERE OVER THE RAINBOW' }
        it { is_expected.to redirect_to :default }
        it { is_expected.to remember :default }
        it { is_expected.to remember_country 'SOMEWHERE OVER THE RAINBOW' }
      end
    end

    context 'with valid session memory' do
      let(:request_session) { :default }
      let(:country_code) { 'US' }
      it { is_expected.to redirect_to :default }
      it { is_expected.to remember :default }
      it { is_expected.to remember_country 'US' }
    end

    context 'with invalid session memory' do
      let(:request_session) { 'foo' }
      let(:country_code) { 'US' }

      it 'removes invalid session data' do
        expect(session['geo_redirect']).not_to eq('foo')
      end

      it { is_expected.to redirect_to :us }
      it { is_expected.to remember :us }
      it { is_expected.to remember_country 'US' }
    end

    context 'with forced redirect flag' do
      let(:country_code) { 'US' }
      let(:request_args) { { redirect: 1 } }

      it { is_expected.to redirect_to :il }
      it 'rewrites the flag out' do
        expect(subject.headers['Location']).not_to include('redirect=1')
      end

      it { is_expected.to remember :il }
      it { is_expected.to remember_country nil }
    end

    context 'with skip flag' do
      let(:country_code) { 'US' }
      let(:request_args) { { skip_geo: true } }
      it { is_expected.to not_redirect }
      it { is_expected.to remember nil }
      it { is_expected.to remember_country nil }

      context 'and with redirect_later option set to false' do
        let(:app_options) { { redirect_later: false } }
        let(:country_code) { 'IL' }
        let(:request_args) { { skip_geo: true } }
        it { is_expected.to not_redirect }
        it { is_expected.to remember :il }
        it { is_expected.to remember_country nil }
      end

      context 'and with redirect_later option set to true' do
        let(:app_options) { { redirect_later: true } }
        let(:country_code) { 'IL' }
        let(:request_args) { { skip_geo: true } }
        it { is_expected.to not_redirect }
        it { is_expected.to remember nil }
        it { is_expected.to remember_country nil }
      end
    end

    context 'with no recognizable IP' do
      let(:country_code) { nil }
      it { is_expected.to not_redirect }
      it { is_expected.to remember nil }
      it { is_expected.to remember_country nil }
    end

    context 'with skip_if block' do
      let(:country_code) { 'US' }

      context 'when returns true' do
        let(:app_options) { { skip_if: ->(_req) { true } } }
        it { is_expected.to not_redirect }
        it { is_expected.to remember nil }
        it { is_expected.to remember_country nil }
      end

      context 'when returns false' do
        let(:app_options) { { skip_if: ->(_req) { false } } }
        it { is_expected.to redirect_to :us }
        it { is_expected.to remember :us }
        it { is_expected.to remember_country 'US' }
      end
    end

    describe 'include/exclude logic' do
      let(:country_code) { 'US' }

      shared_examples :skips_redirect do
        it { is_expected.to not_redirect }
        it { is_expected.to remember nil }
        it { is_expected.to remember_country nil }
      end

      shared_examples :does_not_skip_redirect do
        it { is_expected.to redirect_to :us }
        it { is_expected.to remember :us }
        it { is_expected.to remember_country 'US' }
      end

      context 'with an include option' do
        let(:app_options) { { include: include_value } }

        context 'when include is an array of paths' do
          let(:include_value) { %w(/include_me /include_me/too) }

          context 'when request URL matches one of the included paths' do
            let(:request_path) { '/include_me?query_param=value' }
            it_behaves_like :does_not_skip_redirect
          end

          context 'when request URL does not match any of the included paths' do
            let(:request_path) { '/dont_include_me?query_param=value' }
            it_behaves_like :skips_redirect
          end
        end

        context 'when include is a single path' do
          let(:include_value) { '/include_me' }

          context 'when request URL matches one of the included paths' do
            let(:request_path) { '/include_me?query_param=value' }
            it_behaves_like :does_not_skip_redirect
          end

          context 'when request URL does not match any of the included paths' do
            let(:request_path) { '/dont_include_me?query_param=value' }
            it_behaves_like :skips_redirect
          end
        end
      end

      context 'with an exclude option' do
        let(:app_options) { { exclude: exclude_value } }

        context 'when exclude is an array of paths' do
          let(:exclude_value) { %w(/exclude_me /exclude_me/too) }

          context 'when request URL matches one of the excluded paths' do
            let(:request_path) { '/exclude_me?query_param=value' }
            it_behaves_like :skips_redirect
          end

          context 'when request URL does not match any of the excluded paths' do
            let(:request_path) { '/dont_exclude_me?query_param=value' }
            it_behaves_like :does_not_skip_redirect
          end
        end

        context 'when exclude is a single path' do
          let(:exclude_value) { '/exclude_me' }

          context 'when request URL matches the excluded path' do
            let(:request_path) { '/exclude_me?query_param=value' }
            it_behaves_like :skips_redirect
          end

          context 'when request URL does not match any of the excluded paths' do
            let(:request_path) { '/dont_exclude_me?query_param=value' }
            it_behaves_like :does_not_skip_redirect
          end
        end
      end
    end
  end
end

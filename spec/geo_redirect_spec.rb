require "spec_helper"
require "tempfile"
require "logger"

describe "geo_redirect" do
  include GeoRedirect::Support
  include Rack::Test::Methods

  def session
    last_request.env['rack.session'] || {}
  end

  def url_scheme
    last_request.env['rack.url_scheme']
  end

  before :each do
    @config = YAML.load_file(fixture_path("config.yml"))
  end

  describe "#load_config" do
    it "reads a config file" do
      mock_app

      @app.config.should_not be_nil
      @app.config.should eq(@config)
    end

    it "errors on not-found config file" do
      mock_app :config => nonexisting_file_path
      log_should_include("ERROR")
      log_should_include("Could not load GeoRedirect config YML file")
    end

    it "errors on a mal-formatted config file" do
      mock_app :config => fixture_path("config.bad.yml")
      log_should_include("ERROR")
      log_should_include("Could not load GeoRedirect config YML file")
    end
  end

  describe "#load_db" do
    it "reads a db file" do
      mock_app

      @app.db.should_not be_nil
      @app.db.should be_a_kind_of GeoIP
    end

    it "errors on not-found db file" do
      mock_app :db => nonexisting_file_path
      log_should_include("ERROR")
      log_should_include("Could not load GeoIP database file.")
    end

    # this example is disabled, as it seems that
    # GeoIP does not let me know if a db file is proper.
=begin
    it "errors on mal-formatted db file" do
      pending "GeoIP does not raise on bad files"
      mock_app :db => fixture_path("config.yml")
      log_should_include("ERROR")
      log_should_include("Could not load GeoIP database file.")
    end
=end
  end

  describe "#log" do
    describe "with valid logfile path" do
      before :each do
        mock_app
      end

      it "initiates a log file" do
        @app.instance_variable_get(:"@logger").should be_kind_of Logger
      end

      it "prints to log file" do
        message = "Testing GeoRedirect logger"
        @app.send(:log, [message])
        log_should_include(message)
      end
    end

    it "ignores invalid logfile path" do
      mock_app :logfile => '/no_such_file'
      @app.instance_variable_get(:"@logger").should be_nil
    end
  end

  describe "#host_by_country" do
    before :each do
      mock_app
    end

    it "fetches host by country" do
      @app.host_by_country("US").should eq(:us)
      @app.host_by_country("IL").should eq(:il)
    end

    it "falls back to default" do
      @app.host_by_country(:foo).should eq(:default)
    end
  end

  describe "host_by_hostname" do
    before :each do
      mock_app
    end

    it "fetches host by hostname" do
      @app.host_by_hostname("biz.waze.com").should eq(:us)
      @app.host_by_hostname("biz.waze.co.il").should eq(:il)
      @app.host_by_hostname("biz.world.waze.com").should eq(:world)
    end

    it "falls back to default" do
      @app.host_by_hostname("foo").should eq(:default)
    end
  end

  describe "redirect logic" do
    before :each do
      mock_app
    end

    def mock_request_from(code, options={})
      ip = "5.5.5.5"

      if code.nil?
        country = nil
      else
        country = GeoIP::Country.stub({ :country_code2 => code,
                                        :country_code => 5 })
      end
      @app.db.stub(:country).with(ip).and_return(country)

      env = { "REMOTE_ADDR" => ip, "HTTP_HOST" => "biz.waze.co.il" }

      if options[:session]
        env['rack.session'] ||= {}
        env['rack.session']['geo_redirect'] = options[:session]
        env['rack.session']['geo_redirect.country'] = code
      end

      args = {}
      args[:redirect] = 1 if options[:force]
      args[:skip_geo] = true if options[:skip]

      get "/", args, env
    end

    def should_redirect_to(host)
      last_response.body.should include("Moved Permanently")
      last_response.status.should eq(301)
      last_response.headers.should have_key("Location")
      url = "#{url_scheme}://#{@config[host][:host]}"
      last_response.headers["Location"].should start_with(url)
    end

    def should_not_redirect
      last_response.body.should include("Hello world!")
      last_response.should be_ok
    end

    def should_remember(host)
      session['geo_redirect'].should eq(host)
    end

    def should_remember_country(country)
      session['geo_redirect.country'].should eq(country)
    end

    describe "without session memory" do
      describe "for a foreign source" do
        before :each do
          mock_request_from "US"
        end

        it "redirects to destination" do
          should_redirect_to :us
        end

        it "stores decision in session" do
          should_remember :us
        end

        it "stores discovered country in session" do
          should_remember_country "US"
        end
      end

      describe "for a local source" do
        before :each do
          mock_request_from "IL"
        end

        it "does not redirect" do
          should_not_redirect
        end

        it "stores decision in session" do
          should_remember :il
        end

        it "stores discovered country in session" do
          should_remember_country "IL"
        end
      end

      describe "for an unknown source" do
        before :each do
          mock_request_from "SOMEWHERE OVER THE RAINBOW"
        end

        it "redirects to default" do
          should_redirect_to :default
        end

        it "stores decision in session" do
          should_remember :default
        end

        it "stores discovered country in session" do
          should_remember_country "SOMEWHERE OVER THE RAINBOW"
        end
      end
    end

    describe "with valid session memory" do
      before :each do
        mock_request_from "US", :session => :default
      end

      it "redirects to remembered destination" do
        should_redirect_to :default
      end

      it "leaves session as is" do
        should_remember :default
      end

      it "remembers discovered country" do
        should_remember_country "US"
      end
    end

    describe "with invalid session memory" do
      before :each do
        mock_request_from "US", :session => "foo"
      end

      it "removes invalid session data" do
        session['geo_redirect'].should_not eq("foo")
      end

      it "redirects to destination" do
        should_redirect_to :us
      end

      it "stores decision in session" do
        should_remember :us
      end

      it "stores discovered country in session" do
        should_remember_country "US"
      end
    end

    describe "with forced redirect flag" do
      before :each do
        mock_request_from "US", :force => true
      end

      it "rewrites the flag out" do
        should_redirect_to :il
        last_response.headers["Location"].should_not include("redirect=1")
      end

      it "stores decision in session" do
        should_remember :il
      end

      it "does not store discovered country in session" do
        should_remember_country nil
      end
    end

    describe "with skip flag" do
      before :each do
        mock_request_from "US", :skip => true
      end

      it "does not store decision in session" do
        should_remember nil
      end

      it "does not store discovered country in session" do
        should_remember_country nil
      end

      it "does not redirect" do
        should_not_redirect
      end
    end

    describe "with no recognizable IP" do
      before :each do
        mock_request_from nil
      end

      it "does not redirect" do
        should_not_redirect
      end

      it "does not store session" do
        should_remember nil
      end

      it "does not store discovered country in session" do
        should_remember_country nil
      end
    end
  end
end

describe "geo_redirect:fetch_db" do
  include_context "rake"

  it "downloads a GeoIP db to a location" do
    @dbfile = Tempfile.new("db")
    subject.invoke(@dbfile.path)
    @dbfile.size.should_not be_nil
    @dbfile.size.should be > 0
  end
end

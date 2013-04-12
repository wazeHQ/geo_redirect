require "spec_helper"
require "logger"
require "tempfile"

describe GeoRedirect do
  include GeoRedirect::Support
  include Rack::Test::Methods

  def session
    last_request.env['rack.session']
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

    it "raises on not-found config file" do
      expect {
        mock_app :config => nonexisting_file_path
      }.to raise_error
    end

    it "raises on a mal-formatted config file" do
      expect {
        mock_app :config => fixture_path("config.bad.yml")
      }.to raise_error
    end
  end

  describe "#load_db" do
    it "reads a db file" do
      mock_app

      @app.db.should_not be_nil
      @app.db.should be_a_kind_of GeoIP
    end

    it "raises on not-found db file" do
      expect {
        mock_app :db => nonexisting_file_path
      }.to raise_error
    end

    it "raises on mal-formatted db file" do
      pending "GeoIP does not raise on bad files"
      expect {
        mock_app :db => fixture_path("config.yml")
      }.to raise_error
    end
  end

  describe "#log" do
    describe "with valid logfile path" do
      before :each do
        @logfile = Tempfile.new("log")
        mock_app :logfile => @logfile.path
      end

      it "initiates a log file" do
        @app.instance_variable_get(:"@logfile").should eq(@logfile.path)
        @app.instance_variable_get(:"@logger").should be_kind_of Logger
      end

      it "prints to log file" do
        message = "Testing GeoRedirect logger"
        @app.send(:log, [message])
        @logfile.open do
          @logfile.read.should include(message)
        end
      end
    end

    it "raises on invalid logfile path" do
      expect {
        mock_app :logfile => '/no_such_file'
      }.to raise_error
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

    def mock_request_from(country, options={})
      ip = "5.5.5.5"
      country = GeoIP::Country.stub({ :country_code2 => country,
                                      :country_code => 5 })
      @app.db.stub(:country).with(ip).and_return(country)

      env = { "REMOTE_ADDR" => ip, "HTTP_HOST" => "biz.waze.co.il" }

      if options[:session]
        env['rack.session'] ||= {}
        env['rack.session']['geo_redirect'] = options[:session]
      end

      args = {}
      if options[:force]
        args[:redirect] = 1
      end

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
    end

  end
end

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

    describe "without session memory" do
      describe "for a foreign source" do
        before :each do
          ip = "5.5.5.5"
          country = GeoIP::Country.stub(:country_code2 => "US", :country_code => 225)
          @app.db.should_receive(:country).with(ip).and_return(country)

          get "/", {}, "REMOTE_ADDR" => ip
        end

        it "redirects to destination" do
          last_response.body.should include("Moved Permanently")
          last_response.status.should eq(301)
          last_response.headers.should have_key("Location")
          last_response.headers["Location"].should start_with("#{url_scheme}://#{@config[:us][:host]}")
        end

        it "stores decision in session" do
          session['geo_redirect'].should eq(:us)
        end
      end

      describe "for a local source" do
        it "does not redirect"
        it "stores decision in session"
      end

      describe "for a unknown source" do
        it "does not redirect"
        it "stores decision in session"
      end
    end

    describe "with session memory" do
      it "respects decision in session"
    end

    describe "with forced redirect flag" do
      it "does not redirect"
      it "stores decision in session"
    end

  end
end

require "spec_helper"

describe GeoRedirect do
  include GeoRedirect::Support

  describe "#load_config" do
    it "reads a config file" do
      mock_app

      @app.config.should_not be_nil
      @app.config.should eq YAML.load_file(fixture_path("config.yml"))
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
        puts @app.instance_variable_get(:"@logger")
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

  describe "redirect logic" do
    before :each do
      mock_app
    end

    describe "without session memory" do
      describe "for a foreign source" do
        it "redirects to destination"
        it "stores decision in session"
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

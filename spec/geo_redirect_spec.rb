require "spec_helper"

describe GeoRedirect do
  include GeoRedirect::Support

  describe "#load_config" do
    it "reads a config file" do
      mock_app

      @app.config.should_not be_nil
      @app.config.should eq({
        :us => { :host => 'biz.waze.com',   :countries => ['US', 'CA'] },
        :il => { :host => 'biz.waze.co.il', :countries => ['IL'] },
        :world =>   { :host => 'biz-world.waze.com' },
        :default => { :host => 'biz-world.waze.com' },
      })
    end

    it "raises on not-found config file" do
      expect {
        mock_app :config => '/no_such_file'
      }.to raise_error
    end

    it "raises on a mal-formatted config file" do
      expect {
        mock_app :config => 'spec/fixtures/config.bad.yml'
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
        mock_app :db => '/no_such_file'
      }.to raise_error
    end

    it "raises on mal-formatted db file" do
      pending "GeoIP does not raise on bad files"
      expect {
        mock_app :db => 'spec/fixtures/config.yml'
      }.to raise_error
    end
  end

  describe "#log" do
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
end

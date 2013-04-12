require "spec_helper"

describe GeoRedirect do
  include GeoRedirect::Support

  describe "#load_config" do

    it "reads a config file successfully" do
      mock_app

      @app.config.should_not be_nil
      @app.config.should eq({
        :us => {
          :host => 'biz.waze.com',
          :countries => ['US', 'CA'],
        },
        :il => {
          :host => 'biz.waze.co.il',
          :countries => ['IL'],
        },
        :world => {
          :host => 'biz-world.waze.com',
        },
        :default => {
          :host => 'biz-world.waze.com',
        },
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
end

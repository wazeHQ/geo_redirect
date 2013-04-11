require 'helper'

class TestGeoRedirect < Test::Unit::TestCase

  should 'read config file' do
    mock_app

    assert_not_nil @app.config
    assert_equal @app.config, {
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
    }
  end

  should 'raise on not-found config file' do
    assert_raise Errno::ENOENT do
      mock_app :config => '/nosuchfile'
    end
  end

  should 'raise on a mal-formatted config file' do
    assert_raise Errno::EINVAL do
      mock_app :config => 'test/fixtures/config.bad.yml'
    end
  end

end

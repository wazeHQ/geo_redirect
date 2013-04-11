require 'helper'

class TestGeoRedirect < Test::Unit::TestCase

  context 'no options' do
    setup { mock_app }

    should 'test well' do
      assert true
    end
  end

end

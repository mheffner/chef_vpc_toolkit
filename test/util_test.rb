require File.dirname(__FILE__) + '/test_helper'

module ChefVPCToolkit

class UtilTest < Test::Unit::TestCase

  def test_hostname

    assert_not_nil Util.hostname

  end

end

end

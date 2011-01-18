require File.dirname(__FILE__) + '/test_helper'

module ChefVPCToolkit

class ServerTest < Test::Unit::TestCase

  include ChefVPCToolkit::CloudServersVPC

  def setup
    @tmp_dir=TmpDir.new_tmp_dir
    ServerGroup.data_dir=@tmp_dir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_vpn_server_rebuild_fails
    group=ServerGroup.from_xml(SERVER_GROUP_XML)
    server=group.server("login1")
    assert_raises(RuntimeError) do
        server.rebuild
    end
  end

  def test_rebuild
    group=ServerGroup.from_xml(SERVER_GROUP_XML)
    server=group.server("test1")
    HttpUtil.stubs(:post).returns("")
    server.rebuild
  end



end

end

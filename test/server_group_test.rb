require File.dirname(__FILE__) + '/test_helper'

require 'fileutils'
require 'tempfile'

module ChefVPCToolkit
module CloudServersVPC

class ServerGroupTest < Test::Unit::TestCase

  def setup
    @tmp_dir=TmpDir.new_tmp_dir
    ServerGroup.data_dir=@tmp_dir
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  TEST_JSON_CONFIG = %{{
        "name": "test",
        "domain_name": "vpc",
        "description": "test description",
        "servers": {
            "login": {
                "image_id": "51",
                "flavor_id": "2",
                "openvpn_server": "true"
            },
            "client1": {
                "image_id": "69",
                "flavor_id": "3"
            }
        }
    }}

  def test_server_new
    sg=ServerGroup.new(:name => "test", :domain_name => "vpc", :description => "zz")
    assert_equal "test", sg.name
    assert_equal "zz", sg.description
    assert_equal "vpc", sg.domain_name
    assert_equal "172.19.0.0", sg.vpn_network
    assert_equal "255.255.128.0", sg.vpn_subnet
  end

  def test_vpn_gateway_ip
    sg=ServerGroup.from_xml(SERVER_GROUP_XML)
    assert_equal "184.106.205.120", sg.vpn_gateway_ip
    assert_equal 1759, sg.id
    assert_equal "test description", sg.description
    assert_equal "dan.prince", sg.owner_name
    assert_equal "172.19.0.0", sg.vpn_network
    assert_equal "255.255.128.0", sg.vpn_subnet
    assert_equal 2, sg.servers.size
  end

  def test_vpn_gateway_name
    sg=ServerGroup.from_xml(SERVER_GROUP_XML)
    assert_equal "login1", sg.vpn_gateway_name
  end

  def test_server_group_from_json_config
    sg=ServerGroup.from_json_config(TEST_JSON_CONFIG)
    assert_equal "vpc", sg.domain_name
    assert_equal "test", sg.name
    assert_equal "test description", sg.description
    assert_equal 2, sg.servers.size
    assert_equal 1, sg.ssh_public_keys.size

    # validate the login server
    login_server=sg.server("login") 
    assert_equal 51, login_server.image_id
    assert_equal 2, login_server.flavor_id
    assert_equal true, login_server.openvpn_server?

    # validate the client1 server
    client1_server=sg.server("client1") 
    assert_equal 69, client1_server.image_id
    assert_equal 3, client1_server.flavor_id
    assert_equal false, client1_server.openvpn_server?

  end

  def test_server_group_from_xml
    sg=ServerGroup.from_xml(SERVER_GROUP_XML)
    assert_equal "mydomain.net", sg.domain_name
    assert_equal "test", sg.name
    assert_equal "test description", sg.description
    assert_equal 2, sg.servers.size
    assert_equal 1759, sg.id
  end

  def test_server_group_to_xml
    sg=ServerGroup.from_xml(SERVER_GROUP_XML)
    assert_equal "mydomain.net", sg.domain_name
    assert_equal "test", sg.name
    assert_equal "test description", sg.description
    assert_equal 2, sg.servers.size
    assert_equal 1759, sg.id
    xml=sg.to_xml
  end

  def test_print_server_group

    sg=ServerGroup.from_xml(SERVER_GROUP_XML)
    tmp = Tempfile.open('chef-cloud-toolkit')
    begin
        $stdout = tmp
        sg.pretty_print
        tmp.flush
        output=IO.read(tmp.path)
        $stdout = STDOUT
        assert output =~ /login1/
        assert output =~ /test1/
        assert output =~ /184.106.205.120/
    ensure
        $stdout = STDOUT
    end

  end

  def test_server_names

    sg=ServerGroup.from_xml(SERVER_GROUP_XML)
    names=sg.server_names

    assert_equal 2, names.size
    assert names.include?("login1")
    assert names.include?("test1")

  end

  def test_fetch

    tmp_dir=TmpDir.new_tmp_dir
    File.open("#{tmp_dir}/5.xml", 'w') do |f|
        f.write(SERVER_GROUP_XML)
    end
    ServerGroup.data_dir=tmp_dir

    HttpUtil.stubs(:get).returns(SERVER_GROUP_XML)

    sg=ServerGroup.fetch
    assert_not_nil sg
    assert_equal "test", sg.name

    sg=ServerGroup.fetch(:id => "1234")
    assert_not_nil sg
    assert_equal "test", sg.name

    sg=ServerGroup.fetch(:id => "5", :source => "cache")
    assert_not_nil sg
    assert_equal "test", sg.name

    #nonexistent group from cache
    ENV['GROUP_ID']="1234"
    assert_raises(RuntimeError) do
      ServerGroup.fetch(:source => "cache")
    end

    #invalid fetch source
    assert_raises(RuntimeError) do
      ServerGroup.fetch(:id => "5", :source => "asdf")
    end

  end

  def test_create

    sg=ServerGroup.from_json_config(TEST_JSON_CONFIG)

    HttpUtil.stubs(:post).returns(SERVER_GROUP_XML)
    sg=ServerGroup.create(sg)
    assert_not_nil sg
    assert_equal "mydomain.net", sg.domain_name
    assert_equal "test", sg.name
    assert_equal "test description", sg.description
    assert_equal 2, sg.servers.size
    assert_equal 1759, sg.id

  end

  def test_most_recent

    File.open("#{ServerGroup.data_dir}/5.xml", 'w') do |f|
        f.write(SERVER_GROUP_XML)
    end

    sg=ServerGroup.most_recent

    assert_equal "mydomain.net", sg.domain_name
    assert_equal 1759, sg.id
    assert_equal 2, sg.servers.size

  end

  def test_os_types

    sg=ServerGroup.from_xml(SERVER_GROUP_XML)
    os_types=sg.os_types

    assert_equal 2, os_types.size
    assert_equal "rhel", os_types["login1"]
    assert_equal "ubuntu", os_types["test1"]

  end

  def test_cache_to_disk

    sg=ServerGroup.from_xml(SERVER_GROUP_XML)
    assert sg.cache_to_disk
    assert File.exists?(File.join(ServerGroup.data_dir, "#{sg.id}.xml"))

  end

  def test_delete

    sg=ServerGroup.from_xml(SERVER_GROUP_XML)
    HttpUtil.stubs(:delete).returns("")
    sg.delete
    assert_equal false, File.exists?(File.join(ServerGroup.data_dir, "#{sg.id}.xml"))

  end

end

end
end

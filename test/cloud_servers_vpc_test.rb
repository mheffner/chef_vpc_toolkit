require File.dirname(__FILE__) + '/test_helper'

require 'tempfile'

module ChefVPCToolkit

class CloudServersVPCTest < Test::Unit::TestCase

  def test_os_types

    hash=CloudServersVPC.server_group_hash(SERVER_GROUP_XML)
    os_types=CloudServersVPC.os_types(hash)

    assert_equal 2, os_types.size
    assert_equal "rhel", os_types["login1"]
    assert_equal "ubuntu", os_types["test1"]

  end

  def test_server_names

    hash=CloudServersVPC.server_group_hash(SERVER_GROUP_XML)
    names=CloudServersVPC.server_names(hash)

    assert_equal 2, names.size
    assert names.include?("login1")
    assert names.include?("test1")

  end

  def test_print_server_group

	hash=CloudServersVPC.server_group_hash(SERVER_GROUP_XML)
	tmp = Tempfile.open('chef-cloud-toolkit')
	begin
		$stdout = tmp
		CloudServersVPC.print_server_group(hash)
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

  def test_most_recent_server_group_hash

	tmp_dir=TmpDir.new_tmp_dir
	File.open("#{tmp_dir}/5.xml", 'w') do |f|
		f.write(SERVER_GROUP_XML)
	end

	hash=CloudServersVPC.most_recent_server_group_hash(File.join(tmp_dir, '*.xml'))

	assert_equal "mydomain.net", hash["domain-name"]
	assert_equal "1759", hash["id"]
	assert_equal 2, hash["servers"].size

  end

  def test_server_group_xml_for_id

	tmp_dir=TmpDir.new_tmp_dir
	File.open("#{tmp_dir}/5.xml", 'w') do |f|
		f.write(SERVER_GROUP_XML)
	end

	configs={
		"cloud_servers_vpc_url" => "http://localhost/",
		"cloud_servers_vpc_username" => "admin",
		"cloud_servers_vpc_password" => "test123"
	}
    HttpUtil.stubs(:get).returns(SERVER_GROUP_XML)
	xml=CloudServersVPC.server_group_xml_for_id(configs, File.join(tmp_dir, '*.xml'))
	assert_not_nil xml
	xml=CloudServersVPC.server_group_xml_for_id(configs, File.join(tmp_dir, '*.xml'),"1759")
	assert_not_nil xml

  end

  def test_rebuild

    response={}
    response.stubs(:code).returns('200')
    HttpUtil.stubs(:post).returns(response)

    hash=CloudServersVPC.server_group_hash(SERVER_GROUP_XML)

    assert_raises(RuntimeError) do
		CloudServersVPC.rebuild(hash, "login1")
	end

	assert "200", CloudServersVPC.rebuild(hash, "test1").code

  end

  def test_create_client

    response={}
    response.stubs(:code).returns('200')
    HttpUtil.stubs(:post).returns(response)

    hash=CloudServersVPC.server_group_hash(SERVER_GROUP_XML)

	assert "200", CloudServersVPC.create_client(hash, "test1").code

  end

  def test_vpn_server_name

    hash=CloudServersVPC.server_group_hash(SERVER_GROUP_XML)
    assert_equal "login1", CloudServersVPC.vpn_server_name(hash)

  end

end

end

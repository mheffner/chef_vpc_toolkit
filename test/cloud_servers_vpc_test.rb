require File.dirname(__FILE__) + '/test_helper'

require 'tempfile'

module ChefVPCToolkit

class CloudServersVPCTest < Test::Unit::TestCase

SERVER_GROUP_XML = %{
<?xml version="1.0" encoding="UTF-8"?>
<server-group>
  <created-at type="datetime">2010-10-15T15:15:58-04:00</created-at>
  <description>test description</description>
  <domain-name>mydomain.net</domain-name>
  <historical type="boolean">false</historical>
  <id type="integer">1759</id>
  <last-used-ip-address>172.19.0.2</last-used-ip-address>
  <name>test</name>
  <owner-name>dan.prince</owner-name>
  <updated-at type="datetime">2010-10-15T15:15:58-04:00</updated-at>
  <user-id type="integer">3</user-id>
  <vpn-network>172.19.0.0</vpn-network>
  <vpn-subnet>255.255.128.0</vpn-subnet>
  <servers type="array">
    <server>
      <account-id type="integer">3</account-id>
      <cloud-server-id-number type="integer">1</cloud-server-id-number>
      <created-at type="datetime">2010-10-15T15:15:58-04:00</created-at>
      <description>login1</description>
      <error-message nil="true"></error-message>
      <external-ip-addr>184.106.205.120</external-ip-addr>
      <flavor-id type="integer">4</flavor-id>
      <historical type="boolean">false</historical>
      <id type="integer">5513</id>
      <image-id type="integer">14</image-id>
      <internal-ip-addr>10.179.107.203</internal-ip-addr>
      <name>login1</name>
      <openvpn-server type="boolean">true</openvpn-server>
      <retry-count type="integer">0</retry-count>
      <server-group-id type="integer">1759</server-group-id>
      <status>Online</status>
      <updated-at type="datetime">2010-10-15T15:18:22-04:00</updated-at>
      <vpn-network-interfaces type="array"/>
    </server>
    <server>
      <account-id type="integer">3</account-id>
      <cloud-server-id-number type="integer">2</cloud-server-id-number>
      <created-at type="datetime">2010-10-15T15:15:58-04:00</created-at>
      <description>test1</description>
      <error-message nil="true"></error-message>
      <external-ip-addr>184.106.205.121</external-ip-addr>
      <flavor-id type="integer">49</flavor-id>
      <historical type="boolean">false</historical>
      <id type="integer">5513</id>
      <image-id type="integer">49</image-id>
      <internal-ip-addr>10.179.107.204</internal-ip-addr>
      <name>test1</name>
      <openvpn-server type="boolean">false</openvpn-server>
      <retry-count type="integer">0</retry-count>
      <server-group-id type="integer">1759</server-group-id>
      <status>Online</status>
      <updated-at type="datetime">2010-10-15T15:18:22-04:00</updated-at>
      <vpn-network-interfaces type="array"/>
    </server>
  </servers>
</server-group>
}

  def test_os_types

    #response = mock()
    #response.stubs(:code => "200", :body => json_response)

    #@conn.stubs(:csreq).returns(response)
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

  def test_load_public_key

	key=CloudServersVPC.load_public_key
	assert_not_nil key

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

end

end

require 'json'
require 'builder'
require 'rexml/document'
require 'rexml/xpath'
require 'uuidtools'
require 'ipaddr'
require 'fileutils'
require 'tempfile'

module ChefVPCToolkit

module VpnNetworkManager

	CERT_DIR=File.join(ENV['HOME'], '.pki', 'openvpn')

	def self.configure_gconf(group_hash, client_hash)

		ca_cert=File.join(CERT_DIR, group_hash['id'], 'ca.crt')
		client_cert=File.join(CERT_DIR, group_hash['id'], 'client.crt')
		client_key=File.join(CERT_DIR, group_hash['id'], 'client.key')

		vpn_interface=client_hash['vpn-network-interfaces'][0]

		FileUtils.mkdir_p(File.join(CERT_DIR, group_hash['id']))
		File::chmod(0700, File.join(ENV['HOME'], '.pki'))
		File::chmod(0700, CERT_DIR)

		File.open(ca_cert, 'w') { |f| f.write(vpn_interface['ca-cert']) }
		File.open(client_cert, 'w') { |f| f.write(vpn_interface['client-cert']) }
		File.open(client_key, 'w') do |f|
			f.write(vpn_interface['client-key'])
			f.chmod(0600)
		end

		xml = Builder::XmlMarkup.new
		xml.gconfentryfile do |file|
			file.entrylist({ "base" => "/system/networking/connections/vpc_#{group_hash['id']}"}) do |entrylist|

				entrylist.entry do |entry|
					entry.key("connection/autoconnect")
					entry.value do |value|
						value.bool("false")
					end
				end
				entrylist.entry do |entry|
					entry.key("connection/id")
					entry.value do |value|
						value.string("VPC Group: #{group_hash['id']}")
					end
				end
				entrylist.entry do |entry|
					entry.key("connection/name")
					entry.value do |value|
						value.string("connection")
					end
				end
				entrylist.entry do |entry|
					entry.key("connection/timestamp")
					entry.value do |value|
						value.string(Time.now.to_i.to_s)
					end
				end
				entrylist.entry do |entry|
					entry.key("connection/type")
					entry.value do |value|
						value.string("vpn")
					end
				end
				entrylist.entry do |entry|
					entry.key("connection/uuid")
					entry.value do |value|
						value.string(UUIDTools::UUID.random_create)
					end
				end
				entrylist.entry do |entry|
					entry.key("ipv4/addresses")
					entry.value do |value|
						value.list("type" => "int") do |list|
						end
					end
				end
				entrylist.entry do |entry|
					entry.key("ipv4/dns")
					entry.value do |value|
						value.list("type" => "int") do |list|
							ip=IPAddr.new(group_hash['vpn-network'].chomp("0")+"1")
							list.value do |lv|
								lv.int(ip_to_integer(ip.to_s))
							end
						end
					end
				end
				entrylist.entry do |entry|
					entry.key("ipv4/dns-search")
					entry.value do |value|
						value.list("type" => "string") do |list|
							list.value do |lv|
								lv.string(group_hash['domain-name'])
							end
						end
					end
				end
				entrylist.entry do |entry|
					entry.key("ipv4/ignore-auto-dns")
					entry.value do |value|
						value.bool("true")
					end
				end
				entrylist.entry do |entry|
					entry.key("ipv4/method")
					entry.value do |value|
						value.string("auto")
					end
				end
				entrylist.entry do |entry|
					entry.key("ipv4/name")
					entry.value do |value|
						value.string("ipv4")
					end
				end
				entrylist.entry do |entry|
					entry.key("ipv4/never-default")
					entry.value do |value|
						value.bool("true")
					end
				end
				entrylist.entry do |entry|
					entry.key("ipv4/routes")
					entry.value do |value|
						value.list("type" => "int") do |list|
						end
					end
				end
				entrylist.entry do |entry|
					entry.key("vpn/ca")
					entry.value do |value|
						value.string(ca_cert)
					end
				end
				entrylist.entry do |entry|
					entry.key("vpn/cert")
					entry.value do |value|
						value.string(client_cert)
					end
				end
				entrylist.entry do |entry|
					entry.key("vpn/comp-lzo")
					entry.value do |value|
						value.string("yes")
					end
				end
				entrylist.entry do |entry|
					entry.key("vpn/connection-type")
					entry.value do |value|
						value.string("tls")
					end
				end
				entrylist.entry do |entry|
					entry.key("vpn/key")
					entry.value do |value|
						value.string(client_key)
					end
				end
				entrylist.entry do |entry|
					entry.key("vpn/proto-tcp")
					entry.value do |value|
						value.string("yes")
					end
				end
				entrylist.entry do |entry|
					entry.key("vpn/remote")
					entry.value do |value|
						value.string(group_hash['vpn-gateway'])
					end
				end
				entrylist.entry do |entry|
					entry.key("vpn/service-type")
					entry.value do |value|
						value.string("org.freedesktop.NetworkManager.openvpn")
					end
				end
			end

		end

		Tempfile.open('w') do |f|
			f.write(xml.target!)
			f.flush
			puts %x{gconftool-2 --load #{f.path}}
		end

		return true

	end

	def self.unset_gconf_config(server_group_id)
		puts %x{gconftool-2 --recursive-unset /system/networking/connections/vpc_#{server_group_id}}
	end

	def self.delete_certs(server_group_id)
		FileUtils.rm_rf(File.join(CERT_DIR, server_group_id))
	end

	def self.connect(server_group_id)
		puts %x{#{sudo_display} nmcli con up id "VPC Group: #{server_group_id}"}
	end

	def self.disconnect(server_group_id)
		puts %x{#{sudo_display} nmcli con down id "VPC Group: #{server_group_id}"}
	end

	def self.ip_to_integer(ip_string)
		return 0 if ip_string.nil?
		ip_arr=ip_string.split(".").collect{ |s| s.to_i }
		return ip_arr[0] + ip_arr[1]*2**8 + ip_arr[2]*2**16 + ip_arr[3]*2**24
	end

	def self.sudo_display
		if ENV['DISPLAY'].nil? or ENV['DISPLAY'] != ":0.0" then
			"sudo"
		else
			""
		end
	end

end
end

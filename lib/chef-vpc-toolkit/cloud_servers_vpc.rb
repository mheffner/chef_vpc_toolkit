require 'json'
require 'builder'
require 'rexml/document'
require 'rexml/xpath'

module ChefVPCToolkit

module CloudServersVPC

	SERVER_GROUP_CONFIG_FILE = CHEF_VPC_PROJECT + File::SEPARATOR + "config" + File::SEPARATOR + "server_group.json"

	def self.load_public_key

		ssh_dir=ENV['HOME']+File::SEPARATOR+".ssh"+File::SEPARATOR
		if File.exists?(ssh_dir+"id_rsa.pub")
			pubkey=IO.read(ssh_dir+"id_rsa.pub")
		elsif File.exists?(ssh_dir+"id_dsa.pub")
			pubkey=IO.read(ssh_dir+"id_dsa.pub")
		else
			raise "Failed to load SSH key. Please create a SSH public key pair in your HOME directory."
		end

		pubkey.chomp

	end

	# generate a Server Group XML from server_group.json
	def self.server_group_xml(config_file=SERVER_GROUP_CONFIG_FILE, owner=ENV['USER'])

		json_hash=JSON.parse(IO.read(config_file))

		xml = Builder::XmlMarkup.new
		xml.tag! "server-group" do |sg|
			sg.name(json_hash["name"])
			sg.description(json_hash["description"])
			sg.tag! "owner-name", owner
			sg.tag! "domain-name", json_hash["domain_name"]
			if json_hash["vpn_network"] then
				sg.tag! "vpn-network", json_hash["vpn_network"]
			else
				sg.tag! "vpn-network", "172.19.0.0"
			end
			if json_hash["vpn_subnet"] then
				sg.tag! "vpn-subnet", json_hash["vpn_subnet"]
			else
				sg.tag! "vpn-subnet", "255.255.128.0"
			end
			sg.servers("type" => "array") do |servers|
				json_hash["servers"].each_pair do |server_name, server_config|
					servers.server do |server|
						server.name(server_name)
						if server_config["description"] then
							server.description(server_config["description"])
						else
							server.description(server_name)
						end
						server.tag! "flavor-id", server_config["flavor_id"]
						server.tag! "image-id", server_config["image_id"]
						if server_config["openvpn_server"]
							server.tag! "openvpn-server", "true", { "type" => "boolean"}
						end
					end
				end
			end
			sg.tag! "ssh-public-keys", { "type" => "array"} do |ssh_keys|
				ssh_keys.tag! "ssh-public-key" do |ssh_public_key|
					ssh_public_key.description "#{ENV['USER']}'s public key"
					ssh_public_key.tag! "public-key", self.load_public_key
				end
			end
		end
		xml.target!

	end

	def self.server_group_hash(xml)

		hash={}
        dom = REXML::Document.new(xml)
        REXML::XPath.each(dom, "/server-group") do |sg|

			hash["name"]=sg.elements["name"].text
			hash["description"]=sg.elements["description"].text
			hash["id"]=sg.elements["id"].text
			hash["domain-name"]=sg.elements["domain-name"].text
			hash["vpn-network"]=sg.elements["vpn-network"].text
			hash["vpn-subnet"]=sg.elements["vpn-subnet"].text
			hash["servers"]={}
			REXML::XPath.each(dom, "//server") do |server|
				server_name=server.elements["name"].text
				server_attributes={
					"id" => server.elements["id"].text,
					"cloud-server-id-number" => server.elements["cloud-server-id-number"].text,
					"status" => server.elements["status"].text,
					"external-ip-addr" => server.elements["external-ip-addr"].text,
					"internal-ip-addr" => server.elements["internal-ip-addr"].text,
					"error-message" => server.elements["error-message"].text,
					"image-id" => server.elements["image-id"].text,
					"retry-count" => server.elements["retry-count"].text,
					"openvpn-server" => server.elements["openvpn-server"].text
				}
				if server.elements["openvpn-server"].text and server.elements["openvpn-server"].text == "true" and server.elements["external-ip-addr"].text then
					hash["vpn-gateway"]=server.elements["external-ip-addr"].text
				end
				hash["servers"].store(server_name, server_attributes)
			end
		end

		hash

	end

	def self.server_group_xml_for_id(configs, dir, id=nil)

		if id then
			xml=HttpUtil.get(
				configs["cloud_servers_vpc_url"]+"/server_groups/#{id}.xml",
				configs["cloud_servers_vpc_username"],
				configs["cloud_servers_vpc_password"]
			)
		else
			recent_hash=CloudServersVPC.most_recent_server_group_hash(dir)
			raise "No server group files exist." if recent_hash.nil?
			xml=HttpUtil.get(
				configs["cloud_servers_vpc_url"]+"/server_groups/#{recent_hash['id']}.xml",
				configs["cloud_servers_vpc_username"],
				configs["cloud_servers_vpc_password"]
			)

		end

	end

	def self.most_recent_server_group_hash(dir_pattern)
        server_groups=[]
        Dir[dir_pattern].each do  |file|
            server_groups << CloudServersVPC.server_group_hash(IO.read(file))
        end
		if server_groups.size > 0 then
			server_groups.sort { |a,b| b["id"].to_i <=> a["id"].to_i }[0]
		else
			nil
		end
	end

	def self.print_server_group(hash)

		puts "Cloud Group ID: #{hash["id"]}"
		puts "name: #{hash["name"]}"
		puts "description: #{hash["description"]}"
		puts "domain name: #{hash["domain-name"]}"
		puts "VPN gateway IP: #{hash["vpn-gateway"]}"
		puts "Servers:"
		hash["servers"].each_pair do |name, attrs|
			puts "\tname: #{name} (id: #{attrs['cloud-server-id-number']})"
			puts "\tstatus: #{attrs['status']}"
			if attrs["openvpn-server"] and attrs["openvpn-server"] == "true" then
				puts "\tOpenVPN server: #{attrs['openvpn-server']}"
			end
			if attrs["error-message"] then
				puts "\tlast error message: #{attrs['error-message']}"
			end
			puts "\t--"
		end

	end

	def self.server_names(hash)

		names=[]	

		hash["servers"].each_pair do |name, hash|
			if block_given? then
				yield name
			else
				names << name
			end	
		end

		names
		
	end

	# Return the name of the VPN server within a server group
	def self.vpn_server_name(hash)

		hash["servers"].each_pair do |name, hash|
			if hash['openvpn-server'] and hash['openvpn-server'] == "true" then
				if block_given? then
					yield name
				else
					return name
				end
			end	
		end

	end

	# default timeout of 20 minutes
	def self.poll_until_online(group_id, timeout=1200)

		configs=Util.load_configs

		online = false
		count=0
		until online or (count*20) >= timeout.to_i do
			count+=1
			begin
				xml=HttpUtil.get(
					configs["cloud_servers_vpc_url"]+"/server_groups/#{group_id}.xml",
					configs["cloud_servers_vpc_username"],
					configs["cloud_servers_vpc_password"]
				)

				hash=CloudServersVPC.server_group_hash(xml)

				online=true
				hash["servers"].each_pair do |name, attrs|
					if ["Pending", "Rebuilding"].include?(attrs["status"]) then
						online=false
					end
					if attrs["status"] == "Failed" then
						raise "Failed to create server group with the following message: #{attrs['error-message']}"
					end
				end
				if not online
					yield hash if block_given?
					sleep 20
				end
			rescue EOFError
			end
		end
		if (count*20) >= timeout.to_i then
			raise "Timeout waiting for server groups to come online."
		end

	end

	def self.os_types(server_group_hash)

		os_types={}
		server_group_hash["servers"].each_pair do |name, attrs|
			os_type = case attrs["image-id"].to_i
				when 51 # Centos 5.5
					"centos"
				when 187811 # Centos 5.4
					"centos"
				when 71 # Fedora 14
					"fedora"
				when 53 # Fedora 13
					"fedora"
				when 17 # Fedora 12
					"fedora"
				when 14 # RHEL 5.4
					"rhel"
				when 62 # RHEL 5.5
					"rhel"
				when 49 # Ubuntu 10.04
					"ubuntu"
				when 14362 # Ubuntu 9.10
					"ubuntu"
				when 8 # Ubuntu 9.04
					"ubuntu"
				else
					"unknown"
			end
			if block_given? then
				yield name, os_type
			else
				os_types.store(name, os_type)
			end
		end
		os_types

	end

	def self.rebuild(server_group_hash, server_name)

		configs=Util.load_configs

		server_id=nil
		image_id=nil
		server_group_hash["servers"].each_pair do |name, attrs|
			if name == server_name then
				raise "Error: Rebuilding the OpenVPN server is not supported at this time." if attrs["openvpn-server"] == "true"
				server_id=attrs["id"]
				image_id=attrs["image-id"]
			end
		end
		raise "Unable to find server name: #{server_name}" if server_id.nil?
	
		HttpUtil.post(
			configs["cloud_servers_vpc_url"]+"/servers/#{server_id}/rebuild",
			{},
			configs["cloud_servers_vpc_username"],
			configs["cloud_servers_vpc_password"]
		)

	end

	def self.client_hash(xml)

		hash={}
        dom = REXML::Document.new(xml)
        REXML::XPath.each(dom, "/client") do |client|

			hash["name"]=client.elements["name"].text
			hash["description"]=client.elements["description"].text
			hash["id"]=client.elements["id"].text
			hash["status"]=client.elements["status"].text
			hash["server-group-id"]=client.elements["server-group-id"].text
			hash["vpn-network-interfaces"]=[]
			REXML::XPath.each(dom, "//vpn-network-interface") do |vni|
				client_attributes={
					"id" => vni.elements["id"].text,
					"vpn-ip-addr" => vni.elements["vpn-ip-addr"].text,
					"ptp-ip-addr" => vni.elements["ptp-ip-addr"].text,
					"client-key" => vni.elements["client-key"].text,
					"client-cert" => vni.elements["client-cert"].text,
					"ca-cert" => vni.elements["ca-cert"].text
				}
				hash["vpn-network-interfaces"] << client_attributes
			end
		end

		hash

	end

	def self.poll_client(client_id, timeout=300)

		configs=Util.load_configs

		online = false
		count=0
		until online or (count*5) >= timeout.to_i do
			count+=1
			begin
				xml=HttpUtil.get(
					configs["cloud_servers_vpc_url"]+"/clients/#{client_id}.xml",
					configs["cloud_servers_vpc_username"],
					configs["cloud_servers_vpc_password"]
				)
				hash=CloudServersVPC.client_hash(xml)

				if hash["status"] == "Online" then
					online = true
				else 
					yield hash if block_given?
					sleep 5
				end
			rescue EOFError
			end
		end
		if (count*20) >= timeout.to_i then
			raise "Timeout waiting for client to come online."
		end

	end

	def self.client_xml_for_id(configs, dir, id=nil)

		xml=HttpUtil.get(
			configs["cloud_servers_vpc_url"]+"/clients/#{id}.xml",
			configs["cloud_servers_vpc_username"],
			configs["cloud_servers_vpc_password"]
		)

	end

	def self.create_client(server_group_hash, client_name)

		configs=Util.load_configs

		xml = Builder::XmlMarkup.new
		xml.client do |client|
			client.name(client_name)
			client.description("Toolkit Client: #{client_name}")
			client.tag! "server-group-id", server_group_hash['id']
		end
	
		HttpUtil.post(
			configs["cloud_servers_vpc_url"]+"/clients.xml",
			xml.target!,
			configs["cloud_servers_vpc_username"],
			configs["cloud_servers_vpc_password"]
		)

	end

end

end

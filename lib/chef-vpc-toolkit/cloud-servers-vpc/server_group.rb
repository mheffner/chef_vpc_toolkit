require 'json'
require 'builder'
require 'fileutils'
require 'rexml/document'
require 'rexml/xpath'

module ChefVPCToolkit

module CloudServersVPC

class ServerGroup

	@@data_dir=File.join(CHEF_VPC_PROJECT, "tmp", "server_groups")

	def self.data_dir
		@@data_dir
	end

	def self.data_dir=(dir)
		@@data_dir=dir
	end

	CONFIG_FILE = CHEF_VPC_PROJECT + File::SEPARATOR + "config" + File::SEPARATOR + "server_group.json"

	attr_accessor :id
	attr_accessor :name
	attr_accessor :description
	attr_accessor :domain_name
	attr_accessor :vpn_network
	attr_accessor :vpn_subnet
	attr_accessor :owner_name

	attr_reader :ssh_public_keys

	def initialize(options={})

		@id=options[:id]
		@name=options[:name]
		@description=options[:description]
		@domain_name=options[:domain_name]
		@vpn_network=options[:vpn_network] or @vpn_network="172.19.0.0"
		@vpn_subnet=options[:vpn_subnet] or @vpn_subnet="255.255.128.0"
		@owner_name=options[:owner_name] or @owner_name=ENV['USER']

		@servers=[]
		@ssh_public_keys=[]
    end

	def server(name)
		@servers.select {|s| s.name == name}[0]
	end

	def servers
		@servers
	end

	def vpn_gateway_name
		@servers.select {|s| s.openvpn_server? }[0].name
	end

	def vpn_gateway_ip
		@servers.select {|s| s.openvpn_server? }[0].external_ip_addr
	end

	def ssh_public_keys
		@ssh_public_keys
	end

	# generate a Server Group XML from server_group.json
	def self.from_json_config(json)

		json_hash=JSON.parse(json)

		sg=ServerGroup.new(
			:name => json_hash["name"],
			:description => json_hash["description"],
			:domain_name => json_hash["domain_name"],
			:vpn_network => json_hash["vpn_network"],
			:vpn_subnet => json_hash["vpn_subnet"]
			)
		json_hash["servers"].each_pair do |server_name, server_config|
			sg.servers << Server.new(
				:name => server_name,
				:description => server_config["description"],
				:flavor_id => server_config["flavor_id"],
				:image_id => server_config["image_id"],
				:openvpn_server => server_config["openvpn_server"]
			)
		end

		# automatically add a key for the current user
		sg.ssh_public_keys << SshPublicKey.new(
			:description =>	"#{ENV['USER']}'s public key",
			:public_key => Util.load_public_key

		)

		return sg

	end

	def to_xml

		xml = Builder::XmlMarkup.new
		xml.tag! "server-group" do |sg|
			sg.id(@id)
			sg.name(@name)
			sg.description(@description)
			sg.tag! "owner-name", @owner_name
			sg.tag! "domain-name", @domain_name
			sg.tag! "vpn-network", @vpn_network
			sg.tag! "vpn-subnet", @vpn_subnet
			sg.servers("type" => "array") do |xml_servers|
				self.servers.each do |server|
					xml_servers.server do |xml_server|
						xml_server.name(server.name)
						xml_server.description(server.description)
						xml_server.tag! "flavor-id", server.flavor_id
						xml_server.tag! "image-id", server.image_id
						xml_server.tag! "cloud-server-id-number", server.cloud_server_id_number if server.cloud_server_id_number
						xml_server.tag! "status", server.status if server.status
						xml_server.tag! "external-ip-addr", server.external_ip_addr if server.external_ip_addr
						xml_server.tag! "internal-ip-addr", server.internal_ip_addr if server.internal_ip_addr
						xml_server.tag! "error-message", server.error_message if server.error_message
						xml_server.tag! "retry-count", server.retry_count if server.retry_count
						if server.openvpn_server?
							xml_server.tag! "openvpn-server", "true", { "type" => "boolean"}
						end
					end
				end
			end
			sg.tag! "ssh-public-keys", { "type" => "array"} do |xml_ssh_pub_keys|
				self.ssh_public_keys.each do |ssh_public_key|
					xml_ssh_pub_keys.tag! "ssh-public-key" do |xml_ssh_pub_key|
						xml_ssh_pub_key.description ssh_public_key.description
						xml_ssh_pub_key.tag! "public-key", ssh_public_key.public_key
					end
				end
			end
		end
		xml.target!

	end

	def self.from_xml(xml)

		sg=nil
        dom = REXML::Document.new(xml)
        REXML::XPath.each(dom, "/server-group") do |sg_xml|

			sg=ServerGroup.new(
				:name => XMLUtil.element_text(sg_xml, "name"),
				:id => XMLUtil.element_text(sg_xml, "id").to_i,
				:domain_name => XMLUtil.element_text(sg_xml, "domain-name"),
				:description => XMLUtil.element_text(sg_xml, "description"),
				:vpn_network => XMLUtil.element_text(sg_xml, "vpn-network"),
				:vpn_subnet => XMLUtil.element_text(sg_xml, "vpn-subnet")
			)

			REXML::XPath.each(dom, "//server") do |server_xml|

				server=Server.new(
					:id => XMLUtil.element_text(server_xml, "id").to_i,
					:name => XMLUtil.element_text(server_xml, "name"),
					:cloud_server_id_number => XMLUtil.element_text(server_xml, "cloud-server-id-number"),
					:status => XMLUtil.element_text(server_xml, "status"),
					:external_ip_addr => XMLUtil.element_text(server_xml, "external-ip-addr"),
					:internal_ip_addr => XMLUtil.element_text(server_xml, "internal-ip-addr"),
					:error_message => XMLUtil.element_text(server_xml, "error-message"),
					:image_id => XMLUtil.element_text(server_xml, "image-id"),
					:flavor_id => XMLUtil.element_text(server_xml, "flavor-id"),
					:retry_count => XMLUtil.element_text(server_xml, "retry-count"),
					:openvpn_server => XMLUtil.element_text(server_xml, "openvpn-server")
				)
				sg.servers << server
			end
		end

		sg

	end

	def pretty_print

		puts "Cloud Group ID: #{@id}"
		puts "name: #{@name}"
		puts "description: #{@description}"
		puts "domain name: #{@domain_name}"
		puts "VPN gateway IP: #{self.vpn_gateway_ip}"
		puts "Servers:"
		servers.each do |server|
			puts "\tname: #{server.name} (id: #{server.id})"
			puts "\tstatus: #{server.status}"
			if server.openvpn_server?
				puts "\tOpenVPN server: #{server.openvpn_server?}"
			end
			if server.error_message then
				puts "\tlast error message: #{server.error_message}"
			end
			puts "\t--"
		end

	end

	def server_names

		names=[]	

		servers.each do |server|
			if block_given? then
				yield server.name
			else
				names << server.name
			end	
		end

		names
		
	end

	def cache_to_disk
		FileUtils.mkdir_p(@@data_dir)
        File.open(File.join(@@data_dir, "#{@id}.xml"), 'w') do |f|
            f.chmod(0600)
            f.write(self.to_xml)
        end
	end

	def delete

		configs=Util.load_configs
        HttpUtil.delete(
            configs["cloud_servers_vpc_url"]+"/server_groups/#{@id}.xml",
            configs["cloud_servers_vpc_username"],
            configs["cloud_servers_vpc_password"]
        )
        out_file=File.join(@@data_dir, "#{@id}.xml")
        File.delete(out_file) if File.exists?(out_file)

	end

	# Poll the server group until it is online.
	# :timeout - max number of seconds to wait before raising an exception.
	#            Defaults to 1500
	def poll_until_online(options={})

		timeout=options[:timeout] or timeout = ENV['TIMEOUT']
		if timeout.nil? or timeout.empty? then
			timeout=1500 # defaults to 25 minutes
		end	

		online = false
		count=0
		until online or (count*20) >= timeout.to_i do
			count+=1
			begin
				sg=ServerGroup.fetch(:id => @id, :source => "remote")

				online=true
				sg.servers.each do |server|
					if ["Pending", "Rebuilding"].include?(server.status) then
						online=false
					end
					if server.status == "Failed" then
						raise "Failed to create server group with the following message: #{server.error_message}"
					end
				end
				if not online
					yield sg if block_given?
					sleep 20
				end
			rescue EOFError
			end
		end
		if (count*20) >= timeout.to_i then
			raise "Timeout waiting for server groups to come online."
		end

	end



	def self.create(sg)

		configs=Util.load_configs

		xml=HttpUtil.post(
			configs["cloud_servers_vpc_url"]+"/server_groups.xml",
			sg.to_xml,
			configs["cloud_servers_vpc_username"],
			configs["cloud_servers_vpc_password"]
		)

		sg=ServerGroup.from_xml(xml)
		sg.cache_to_disk
		sg

	end

	# Fetch a server group. The following options are available:
	#
	# :id - The ID of the server group to fetch. Defaults to ENV['GROUP_ID']
	# :source - valid options are 'remote' and 'cache'
	def self.fetch(options={})

		source = options[:source] or source = "remote"
		id=options[:id] or id = ENV['GROUP_ID']
		if id.nil? then
			group=ServerGroup.most_recent
			raise "No server group files exist." if group.nil?
			id=group.id
		end

		if source == "remote" then
			configs=Util.load_configs
			xml=HttpUtil.get(
				configs["cloud_servers_vpc_url"]+"/server_groups/#{id}.xml",
				configs["cloud_servers_vpc_username"],
				configs["cloud_servers_vpc_password"]
			)
			ServerGroup.from_xml(xml)
		elsif source == "cache" then
			out_file=File.join(@@data_dir, "#{id}.xml")
			raise "No server group files exist." if not File.exists?(out_file)
            ServerGroup.from_xml(IO.read(out_file))
		else
			raise "Invalid fetch :source specified."
		end

	end

	def self.most_recent
        server_groups=[]
        Dir[File.join(@@data_dir, "*.xml")].each do  |file|
            server_groups << ServerGroup.from_xml(IO.read(file))
        end
		if server_groups.size > 0 then
			server_groups.sort { |a,b| b.id <=> a.id }[0]
		else
			nil
		end
	end

	def os_types

		os_types={}
		self.servers.each do |server|
			os_type = case server.image_id
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
				when 69 # Ubuntu 10.10
					"ubuntu"
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
				yield server.name, os_type
			else
				os_types.store(server.name, os_type)
			end
		end
		os_types

	end

end

end

end

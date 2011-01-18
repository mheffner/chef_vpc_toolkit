module ChefVPCToolkit

module CloudServersVPC

class Server

	attr_accessor :id
	attr_accessor :name
	attr_accessor :description
	attr_accessor :external_ip_addr
	attr_accessor :internal_ip_addr
	attr_accessor :cloud_server_id_number
	attr_accessor :flavor_id
	attr_accessor :image_id
	attr_accessor :server_group_id
	attr_accessor :openvpn_server
	attr_accessor :retry_count
	attr_accessor :error_message
	attr_accessor :status

	def initialize(options={})

		@id=options[:id].to_i
		@name=options[:name]
		@description=options[:description] or @description=@name
		@external_ip_addr=options[:external_ip_addr]
		@internal_ip_addr=options[:internal_ip_addr]
		@cloud_server_id_number=options[:cloud_server_id_number].to_i
		@flavor_id=options[:flavor_id].to_i
		@image_id=options[:image_id].to_i
		@server_group_id=options[:server_group_id].to_i
		@openvpn_server = [true, "true"].include?(options[:openvpn_server])
		@retry_count=options[:retry_count].to_i or 0
		@error_message=options[:error_message]
		@status=options[:status]

    end

	def openvpn_server?
		return @openvpn_server
	end

	def rebuild

		configs=Util.load_configs

		raise "Error: Rebuilding the OpenVPN server is not supported at this time." if openvpn_server?

		HttpUtil.post(
			configs["cloud_servers_vpc_url"]+"/servers/#{@id}/rebuild",
			{},
			configs["cloud_servers_vpc_username"],
			configs["cloud_servers_vpc_password"]
		)

	end

end

end

end

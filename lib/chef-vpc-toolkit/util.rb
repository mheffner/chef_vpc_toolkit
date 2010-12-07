require 'yaml'

module ChefVPCToolkit

module Util

	def self.load_configs

		config_file=ENV['CHEF_VPC_TOOLKIT_CONF']
		if config_file.nil? then

			config_file=ENV['HOME']+File::SEPARATOR+".chef_vpc_toolkit.conf"
			if not File.exists?(config_file) then
				config_file="/etc/chef_vpc_toolkit.conf"
			end

		end

		if File.exists?(config_file) then
			configs=YAML.load_file(config_file)
			raise_if_nil_or_empty(configs, "cloud_servers_vpc_url")
			raise_if_nil_or_empty(configs, "cloud_servers_vpc_username")
			raise_if_nil_or_empty(configs, "cloud_servers_vpc_password")
			return configs
		else
			raise "Failed to load cloud toolkit config file. Please configure /etc/chef_vpc_toolkit.conf or create a .chef_vpc_toolkit.conf config file in your HOME directory."
		end

	end

	def self.raise_if_nil_or_empty(options, key)
		if options[key].nil? || options[key].empty? then
			raise "Please specify a valid #{key.to_s} parameter."
		end
	end

	def self.hash_for_group(configs=Util.load_configs)

		id=ENV['GROUP_ID']
		configs=Util.load_configs
		hash=nil
		if id.nil? then
			hash=CloudServersVPC.most_recent_server_group_hash(File.join(TMP_SG, '*.xml'))
		else
			file=File.join(TMP_SG, "#{id}.xml")
			hash = CloudServersVPC.server_group_hash(IO.read(file))
		end
		raise "Create a cloud before running this command." if hash.nil?

		hash

	end

end

end

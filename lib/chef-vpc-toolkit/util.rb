require 'yaml'
require 'socket'

module ChefVPCToolkit

module Util

	@@configs=nil

	def self.hostname
		Socket.gethostname
	end

	def self.load_configs

		return @@configs if not @@configs.nil?

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
			@@configs=configs
		else
			raise "Failed to load cloud toolkit config file. Please configure /etc/chef_vpc_toolkit.conf or create a .chef_vpc_toolkit.conf config file in your HOME directory."
		end

		@@configs

	end

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

	def self.raise_if_nil_or_empty(options, key)
		if options[key].nil? || options[key].empty? then
			raise "Please specify a valid #{key.to_s} parameter."
		end
	end

end

end

require 'chef-vpc-toolkit/util'
require 'chef-vpc-toolkit/chef_installer'
require 'chef-vpc-toolkit/ssh_util'
require 'chef-vpc-toolkit/version'
require 'chef-vpc-toolkit/xml_util'
require 'chef-vpc-toolkit/vpn_connection'
require 'chef-vpc-toolkit/vpn_openvpn'
require 'chef-vpc-toolkit/vpn_network_manager'
require 'chef-vpc-toolkit/cloud-servers-vpc/connection'
require 'chef-vpc-toolkit/cloud-servers-vpc/client'
require 'chef-vpc-toolkit/cloud-servers-vpc/server'
require 'chef-vpc-toolkit/cloud-servers-vpc/server_group'
require 'chef-vpc-toolkit/cloud-servers-vpc/ssh_public_key'
require 'chef-vpc-toolkit/cloud-servers-vpc/vpn_network_interface'

module ChefVPCToolkit

        # Loads the appropriate VPN connection type based on
        # the configuration variable 'vpn_connection_type'.
        #
        def self.get_vpn_connection(group, client = nil)
                configs = Util.load_configs
                if "#{configs['vpn_connection_type']}" == "openvpn"
                        VpnOpenVpn.new(group, client)
                else
                        VpnNetworkManager.new(group, client)
                end
        end
end

#require 'chef-cloud-toolkit'
include ChefVPCToolkit::CloudServersVPC

namespace :group do
	TMP_SG=File.join(CHEF_VPC_PROJECT, 'tmp', 'server_groups')
	TMP_CLIENTS=File.join(CHEF_VPC_PROJECT, 'tmp', 'clients')

	directory TMP_SG
	directory TMP_CLIENTS

	task :init => [TMP_SG, TMP_CLIENTS]

	desc "Create a new group of cloud servers"
	task :create => [ "init", "chef:validate_json" ] do

		sg=ServerGroup.from_json_config(IO.read(ServerGroup::CONFIG_FILE))
		sg=ServerGroup.create(sg)
		puts "Server group ID #{sg.id} created."
		
	end

	desc "List existing cloud server groups."
	task :list => "init" do

		server_groups=nil
		if ENV['REMOTE']
			server_groups=ServerGroup.list(:source => "remote")
		else
			server_groups=ServerGroup.list(:source => "cache")
		end
		if server_groups.size > 0
			puts "Server groups:"
			server_groups.sort { |a,b| b.id <=> a.id }.each do |sg|
				gw=sg.vpn_gateway_ip.nil? ? "" : " (#{sg.vpn_gateway_ip})"
				puts "\t :id => #{sg.id}, :name => #{sg.name}, :owner => #{sg.owner_name}#{gw}"
			end
		else
			puts "No server groups."
		end

	end

	desc "Join a group by caching the server group data to disk."
	task :join => [ "init" ] do

		id=ENV['GROUP_ID']
		if id.nil?
			ENV['REMOTE']="true"
			Rake::Task['group:list'].invoke
			puts "Enter ID of group to join:"
			id=STDIN.gets.chomp
		end

		sg=ServerGroup.fetch(:id => id, :source => "remote")
		sg.cache_to_disk
		sg.pretty_print

	end

	desc "Print information for a cloud server group"
	task :show => [ "init" ] do

		sg=ServerGroup.fetch
		sg.cache_to_disk
		sg.pretty_print

	end

	desc "Delete a cloud server group"
	task :delete => ["init", "vpn:delete"] do

		sg=ServerGroup.fetch(:source => "cache")
		SshUtil.remove_known_hosts_ip(sg.vpn_gateway_ip)
		puts "Deleting cloud server group ID: #{sg.id}."
		sg.delete

	end

	desc "Force clean the cached server group files"
	task :force_clean do
		puts "Removing cached server group files."
		FileUtils.rm_rf(TMP_SG)
	end

	desc "Poll/loop until a server group is online"
	task :poll => ["init"] do

		sg=ServerGroup.fetch

		puts "Polling for server(s) to come online (this may take a couple minutes)..."
		old_group_xml=nil
		vpn_gateway=nil
		sg.poll_until_online do |server_group|
			if old_group_xml != server_group.to_xml then
				old_group_xml = server_group.to_xml
				vpn_gateway = server_group.vpn_gateway_ip if server_group.vpn_gateway_ip
				if not vpn_gateway.nil? and not vpn_gateway.empty? then
					SshUtil.remove_known_hosts_ip(vpn_gateway)
				end
				server_group.pretty_print
			end
		end
		Rake::Task['group:show'].invoke
		puts "Server group online."
	end

	desc "Add a single server to the server group."
	task :add_server do
		server_name=ENV['SERVER_NAME']
		image_id=ENV['IMAGE_ID']
		flavor_id=ENV['FLAVOR_ID']
		raise "Please specify a SERVER_NAME." if server_name.nil?
		raise "Please specify a IMAGE_ID." if image_id.nil?
		raise "Please specify a FLAVOR_ID." if flavor_id.nil?
		group=ServerGroup.fetch(:source => "cache")
		server=Server.new(
			:name => server_name,
			:description => server_name,
			:image_id => image_id,
			:flavor_id => flavor_id,
			:server_group_id => group.id
		)
		server=Server.create(server)
		group=ServerGroup.fetch
		group.cache_to_disk
		puts "Server ID #{server.id} created."
	end

	desc "Delete a single server from the server group."
	task :delete_server do
		server_name=ENV['SERVER_NAME']
		raise "Please specify a SERVER_NAME." if server_name.nil?
		group=ServerGroup.fetch(:source => "cache")
		server=group.server(server_name)
		raise "Server with name '#{server_name}' does not exist." if server.nil?
		server.delete
		puts "Server '#{server_name}' deleted."
	end

	desc "Print the VPN gateway IP address"
	task :vpn_gateway_ip do
		group=ServerGroup.fetch(:source => "cache")
		puts group.vpn_gateway_ip
	end

end

namespace :server do

	desc "Rebuild a server in a server group."
	task :rebuild do
		server_name=ENV['SERVER_NAME']
		raise "Please specify a SERVER_NAME." if server_name.nil?
		group=ServerGroup.fetch
		server=group.server(server_name)
		raise "Server with name '#{server_name}' does not exist." if server.nil?
		server.rebuild
	end

end

namespace :chef do

	desc "Validate the Chef JSON config file."
	task :validate_json do

		configs=ChefInstaller.load_configs
		ChefInstaller.validate_json(configs)

	end

	desc "Install and configure Chef on the server group"
	task :install do

		configs=ChefInstaller.load_configs
		configs.merge!(Util.load_configs)
		group=ServerGroup.fetch(:source => "cache")
		configs["ssh_gateway_ip"]=group.vpn_gateway_ip

		server_name=ENV['SERVER_NAME']
		if server_name.nil? then
			client_validation_key=ChefInstaller.install_chef_server(configs, group.os_types)
			ChefInstaller.create_databags(configs)
			ChefInstaller.install_chef_clients(configs, client_validation_key, group.os_types)
		else
			client_validation_key=ChefInstaller.client_validation_key(configs)
			ChefInstaller.install_chef_client(configs, server_name, client_validation_key, group.os_types[server_name])
		end

	end

	desc "Tail the Chef client logs"
	task :tail_logs do
		
		lines=ENV['LINES']
		server=ENV['SERVER_NAME']
		if server and server.empty?
			server=nil
		end
		if lines.nil? or lines.empty? then
			lines=100
		end
		configs=ChefInstaller.load_configs
		group=ServerGroup.fetch(:source => "cache")
		group.server_names do |name|
			if server and server != name
				next
			end

			puts "================================================================================"
			puts "SERVER NAME: #{name}"
			puts ChefInstaller.tail_log(group.vpn_gateway_ip, name, "/var/log/chef/client.log", lines)
		end

	end

	desc "Poll for Chef clients to finish running."
	task :poll_clients do
		
		server_list=ENV['SERVER_NAME']
		timeout=ENV['CHEF_TIMEOUT']
		group=ServerGroup.fetch(:source => "cache")
		if server_list.nil? or server_list.empty?
		    server_list=group.server_names.collect{|x| x+" "}.join.to_s
		end
		if timeout.nil? or timeout.empty?
            timeout=600
        end
		configs=ChefInstaller.load_configs
		configs["ssh_gateway_ip"]=group.vpn_gateway_ip
        puts "Polling for Chef clients to finish running..."
        if not ChefInstaller.poll_clients(configs, server_list, timeout) then
			raise "Chef client timeout."
		end

	end

	#Deprecated
	task :sync_repos => "chef:push_repos"

	desc "Push/Extract cookbook repos to the server group."
	task :push_repos do

		configs=ChefInstaller.load_configs
		group=ServerGroup.fetch(:source => "cache")
		configs["ssh_gateway_ip"]=group.vpn_gateway_ip
		ChefInstaller.rsync_cookbook_repos(configs)

	end

	desc "Pull cookbook repos from the server group to the local project."
	task :pull_repos do

		configs=ChefInstaller.load_configs
		group=ServerGroup.fetch(:source => "cache")
		configs["ssh_gateway_ip"]=group.vpn_gateway_ip
		ChefInstaller.pull_cookbook_repos(configs)

	end

	desc "Create/Update databags on the Chef server."
	task :databags do

		configs=ChefInstaller.load_configs
		group=ServerGroup.fetch(:source => "cache")
		configs["ssh_gateway_ip"]=group.vpn_gateway_ip
		ChefInstaller.create_databags(configs)

	end

end

namespace :share do

	desc "Sync the share data."
	task :sync do

		if File.exists?("#{CHEF_VPC_PROJECT}/share/") then
			puts "Syncing share data."
			group=ServerGroup.fetch(:source => "cache")
			system("rsync -azL '#{CHEF_VPC_PROJECT}/share/' root@#{group.vpn_gateway_ip}:/mnt/share/")
		end

	end

end

namespace :vpn do

	desc "Connect to a server group as a VPN client."
	task :connect do

		puts "Creating VPN Connection..."
		group=ServerGroup.fetch(:source => "cache")
		if not File.exists?(File.join(TMP_CLIENTS, "#{group.id}.xml")) then
			Rake::Task['vpn:create_client'].invoke
			Rake::Task['vpn:poll_client'].invoke
		end
		client=Client.fetch(:id => group.id, :source => "cache")
		ChefVPCToolkit::VpnNetworkManager.configure_gconf(group, client)
		ChefVPCToolkit::VpnNetworkManager.connect(group.id)

	end

	desc "Disconnect from a server group as a VPN client."
	task :disconnect do

		group=ServerGroup.fetch(:source => "cache")
		ChefVPCToolkit::VpnNetworkManager.disconnect(group.id)

		vpn_server_ip=group.vpn_network.chomp("0")+"1"
		SshUtil.remove_known_hosts_ip(vpn_server_ip)
		SshUtil.remove_known_hosts_ip("#{group.vpn_gateway_name},#{vpn_server_ip}")

	end

	desc "Delete VPN config information."
	task :delete do

		group=ServerGroup.fetch(:source => "cache")
		ChefVPCToolkit::VpnNetworkManager.unset_gconf_config(group.id)
		ChefVPCToolkit::VpnNetworkManager.delete_certs(group.id)

		vpn_server_ip=group.vpn_network.chomp("0")+"1"
		SshUtil.remove_known_hosts_ip(vpn_server_ip)
		SshUtil.remove_known_hosts_ip("#{group.vpn_gateway_name},#{vpn_server_ip}")
		begin
			client=Client.fetch(:id => group.id, :source => "cache")
			client.delete if client
		rescue
		end

	end

	desc "Create a new VPN client."
	task :create_client do

		group=ServerGroup.fetch(:source => "cache")
		vpn_client_name=Util.hostname
		configs=Util.load_configs
		if not configs['vpn_client_name'].nil? then
			vpn_client_name=configs['vpn_client_name']
		end

		client=Client.create(group, vpn_client_name, true)
		puts "Client ID #{client.id} created."
		
	end

	desc "Poll until a client is online"
	task :poll_client do

		group=ServerGroup.fetch(:source => "cache")
		client=Client.fetch(:id => group.id, :source => "cache")
		puts "Polling for client VPN cert to be created (this may take a minute)...."
		client.poll_until_online
		client=Client.fetch(:id => client.id, :remote => "cache")
		client.cache_to_disk
		puts "Client VPN certs are ready to use."

	end

end

desc "SSH into the most recently created VPN gateway server."
task :ssh => 'group:init' do

	sg=ServerGroup.fetch(:source => "cache")
	args=ARGV[1, ARGV.length].join(" ")
	if ARGV[1] and ARGV[1] =~ /^GROUP_ID=/
		args=ARGV[2, ARGV.length].join(" ")
	end
	exec("ssh -o \"StrictHostKeyChecking no\" root@#{sg.vpn_gateway_ip} #{args}")
end

desc "Create a server group, install chef, sync share data and cookbooks."
task :create do

	Rake::Task['group:create'].invoke
	Rake::Task['group:poll'].invoke
	Rake::Task['chef:push_repos'].invoke
	Rake::Task['chef:install'].invoke
	#Rake::Task['share:sync'].invoke

end

desc "Rebuild and Re-Chef the specified server."
task :rechef => [ "server:rebuild", "group:poll" ] do
	server_name=ENV['SERVER_NAME']
	raise "Please specify a SERVER_NAME." if server_name.nil?

	configs=ChefInstaller.load_configs
	configs.merge!(Util.load_configs)
	group=ServerGroup.fetch
	os_types=group.os_types
	configs["ssh_gateway_ip"]=group.vpn_gateway_ip
	ChefInstaller.knife_readd_node(configs, server_name)
	client_validation_key=ChefInstaller.client_validation_key(configs)
	ChefInstaller.install_chef_client(configs, server_name, client_validation_key, os_types[server_name])

end

desc "Use rdesktop to connect to Windows servers."
task :rdesktop => 'group:init' do

    server_name=ENV['SERVER_NAME']
    raise "Please specify a SERVER_NAME." if server_name.nil?

    # VPC machines have their public IPs disabled
    # This option is useful for debugging failed VPN connections
    use_public_ip=ENV['PUBLIC_IP']

    sg=ServerGroup.fetch(:source => "cache")
    pass=sg.server(server_name).admin_password

    if use_public_ip.nil? then
		if ChefVPCToolkit::VpnNetworkManager.connected?(sg.id)
            # on the VPN we connect directly to the windows machine
            local_ip=%x{ssh -o \"StrictHostKeyChecking no\" root@#{sg.vpn_gateway_ip} grep #{server_name}.#{sg.domain_name} /etc/hosts | cut -f 1}.chomp
            exec("rdesktop #{local_ip} -u Administrator -p #{pass}")
        else
            # when not on the VPN create an SSH tunnel for rdesktop traffic
            local_ip=%x{ssh -o \"StrictHostKeyChecking no\" root@#{sg.vpn_gateway_ip} grep #{server_name}.#{sg.domain_name} /etc/hosts | cut -f 1}.chomp
            %x{
            ssh root@#{sg.vpn_gateway_ip} -L 1234:#{local_ip}:3389 'sleep 3 & exit' &
            sleep 1
            rdesktop localhost:1234 -u Administrator -p #{pass}
            }
        end
    else
        public_ip=sg.server(server_name).external_ip_addr
        exec("rdesktop #{public_ip} -u Administrator -p #{pass}")
    end

end

desc "Alias to the vpn:connect task."
task :vpn => "vpn:connect"


desc "Print help and usage information"
task :usage do

	puts ""
	puts "Chef VPC Toolkit Version: #{ChefVPCToolkit::Version::VERSION}"
	puts ""
	puts "The following tasks are available:"

	puts %x{cd #{CHEF_VPC_PROJECT} && rake -T}
	puts "----"
	puts "Example commands:"
	puts ""
	puts "\t- Create a new server group, upload cookbooks, install chef\n\ton all the nodes, sync share data and cookbooks."
	puts ""
	puts "\t\t$ rake create"

	puts ""
	puts "\t- List your currently running server groups."
	puts ""
	puts "\t\t$ rake group:list"

	puts ""
	puts "\t- List all remote groups using a common Cloud Servers VPC account."
	puts ""
	puts "\t\t$ rake group:list REMOTE=true"


	puts ""
	puts "\t- SSH into the current (most recently created) server group."
	puts ""
	puts "\t\t$ rake ssh"

	puts ""
	puts "\t- SSH into a server group with an ID of 3."
	puts ""
	puts "\t\t$ rake ssh GROUP_ID=3"

	puts ""
	puts "\t- Delete the server group with an ID of 3."
	puts ""
	puts "\t\t$ rake group:delete GROUP_ID=3"

	puts ""
	puts "\t- Rebuild/Re-Chef a server in the most recently created server group."
	puts ""
	puts "\t\t$ rake rechef SERVER_NAME=db1"

	puts ""

end

task :default => 'usage'

#require 'chef-cloud-toolkit'

namespace :group do
	TMP_SG=File.join(CHEF_VPC_PROJECT, 'tmp', 'server_groups')

	directory TMP_SG

	desc "Create a new group of cloud servers"
	task :create => [ TMP_SG, "chef:validate_json" ] do

		request=CloudServersVPC.server_group_xml
		configs=Util.load_configs

		resp=HttpUtil.post(
			configs["cloud_servers_vpc_url"]+"/server_groups.xml",
			request,
			configs["cloud_servers_vpc_username"],
			configs["cloud_servers_vpc_password"]
		)

		hash=CloudServersVPC.server_group_hash(resp)	
		out_file=hash["id"]+".xml"
		File.open(File.join(TMP_SG, out_file), 'w') { |f| f.write(resp) }
		puts "Cloud server group ID #{hash['id']} created."
		
	end

	desc "List existing cloud server groups"
	task :list => TMP_SG do

		server_groups=[]
		Dir[File.join(TMP_SG, '*.xml')].each do  |file|
			server_groups << CloudServersVPC.server_group_hash(IO.read(file))
		end
		if server_groups.size > 0
			puts "Cloud server groups:"
			server_groups.sort { |a,b| b["id"] <=> a["id"] }.each do |sg|
				gw=sg['vpn-gateway'].nil? ? "" : " (#{sg['vpn-gateway']})"
				puts "\t#{sg['id']}: #{sg['name']}#{gw}"
			end
		else
			puts "No server groups."
		end

	end

	desc "Print information for a cloud server group"
	task :show => TMP_SG do
		id=ENV['GROUP_ID']
		configs=Util.load_configs
		xml=CloudServersVPC.server_group_xml_for_id(configs, File.join(TMP_SG, '*.xml'), id)

		hash=CloudServersVPC.server_group_hash(xml)
		File.open(File.join(TMP_SG, "#{hash['id']}.xml"), 'w') { |f| f.write(xml) }
		CloudServersVPC.print_server_group(hash)

	end

	desc "Delete a cloud server group"
	task :delete do
		id=ENV['GROUP_ID']
		configs=Util.load_configs
		hash=Util.hash_for_group
		if id.nil? then
			id=hash["id"]
		end
		SshUtil.remove_known_hosts_ip(hash["vpn-gateway"])	
		puts "Deleting cloud server group ID: #{id}."
		HttpUtil.delete(
			configs["cloud_servers_vpc_url"]+"/server_groups/#{id}.xml",
			configs["cloud_servers_vpc_username"],
			configs["cloud_servers_vpc_password"]
		)
		File.delete(File.join(TMP_SG, "#{id}.xml"))
	end

	desc "Force clean the cached server group files"
	task :force_clean do
		puts "Removing cached server group files."
		FileUtils.rm_rf(TMP_SG)
	end

	desc "Poll/loop until a server group is online"
	task :poll do
		timeout=ENV['TIMEOUT']
		if timeout.nil? or timeout.empty? then
			timeout=1500 # defaults to 24 minutes
		end
		hash=Util.hash_for_group
		puts "Polling for server(s) to come online (this may take a couple minutes)..."
		servers=nil
		vpn_gateway=nil
		CloudServersVPC.poll_until_online(hash["id"], timeout) do |server_group_hash|
			if servers != server_group_hash then
				servers = server_group_hash
				vpn_gateway = server_group_hash["vpn-gateway"] if server_group_hash["vpn-gateway"]
				if not vpn_gateway.nil? and not vpn_gateway.empty? then
					SshUtil.remove_known_hosts_ip(vpn_gateway)
				end
				ENV["GROUP_ID"]=server_group_hash['id']
				CloudServersVPC.print_server_group(server_group_hash)
			end
		end
		Rake::Task['cloud:show'].invoke
		puts "Cloud server group online."
	end

end

namespace :server do

	desc "Rebuild a server in a server group."
	task :rebuild => TMP_SG do
		id=ENV['GROUP_ID']
		server_name=ENV['SERVER_NAME']
		raise "Please specify a SERVER_NAME." if server_name.nil?
		configs=Util.load_configs

		xml=CloudServersVPC.server_group_xml_for_id(configs, File.join(TMP_SG, '*.xml'), id)
		hash=CloudServersVPC.server_group_hash(xml)
		CloudServersVPC.rebuild(hash, server_name)

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
		hash=Util.hash_for_group(configs)
		os_types=CloudServersVPC.os_types(hash)
		configs["ssh_gateway_ip"]=hash["vpn-gateway"]
		client_validation_key=ChefInstaller.install_chef_server(configs, os_types)
		ChefInstaller.create_databags(configs)
		ChefInstaller.install_chef_clients(configs, client_validation_key, os_types)

	end

	desc "Tail the Chef client logs"
	task :tail_logs do
		
		lines=ENV['LINES']
		if lines.nil? or lines.empty? then
			lines=100
		end
		configs=ChefInstaller.load_configs
		hash=Util.hash_for_group(configs)
		CloudServersVPC.server_names(hash) do |name|
			puts "================================================================================"
			puts "SERVER NAME: #{name}"
			puts ChefInstaller.tail_log(hash["vpn-gateway"], name, "/var/log/chef/client.log", lines)
		end

	end

	desc "Sync the local cookbook repos directory to the Chef server."
	task :sync_repos do

		configs=ChefInstaller.load_configs
		hash=Util.hash_for_group(configs)
		configs["ssh_gateway_ip"]=hash["vpn-gateway"]
		ChefInstaller.rsync_cookbook_repos(configs)

	end

	desc "Create/Update databags on the Chef server."
	task :databags do

		configs=ChefInstaller.load_configs
		hash=Util.hash_for_group(configs)
		configs["ssh_gateway_ip"]=hash["vpn-gateway"]
		ChefInstaller.create_databags(configs)

	end

end

namespace :share do

	desc "Sync the share data."
	task :sync do

		if File.exists?("#{CHEF_VPC_PROJECT}/share/") then
			puts "Syncing share data."
			configs=Util.load_configs
			hash=Util.hash_for_group(configs)
			system("rsync -azL '#{CHEF_VPC_PROJECT}/share/' root@#{hash['vpn-gateway']}:/mnt/share/")
		end

	end

end

desc "SSH into the most recently created VPN gateway server."
task :ssh do
	hash=Util.hash_for_group
	exec("ssh root@#{hash['vpn-gateway']}")
end

desc "Create a server group, install chef, sync share data and cookbooks."
task :create do

	Rake::Task['group:create'].invoke
	Rake::Task['group:poll'].invoke
	Rake::Task['chef:sync_repos'].invoke
	Rake::Task['chef:install'].invoke
	#Rake::Task['share:sync'].invoke

end

desc "Rebuild and Re-Chef the specified server."
task :rechef => [ "server:rebuild", "group:poll" ] do
	server_name=ENV['SERVER_NAME']
	raise "Please specify a SERVER_NAME." if server_name.nil?

	configs=ChefInstaller.load_configs
	configs.merge!(Util.load_configs)
	hash=Util.hash_for_group(configs)
	os_types=CloudServersVPC.os_types(hash)
	configs["ssh_gateway_ip"]=hash["vpn-gateway"]
	ChefInstaller.knife_readd_node(configs, server_name)
	client_validation_key=ChefInstaller.client_validation_key(configs)
	ChefInstaller.install_chef_client(configs, server_name, client_validation_key, os_types[server_name])

end

desc "Print help and usage information"
task :usage do

	puts ""
	puts "Cloud Toolkit Version: #{ChefVPCToolkit::Version::VERSION}"
	puts ""
	puts "The following tasks are available:"

	puts %x{cd #{CHEF_VPC_PROJECT} && rake -T}
	puts "----"
	puts "Example commands:"
	puts ""
	puts "\t- Create a new cloud server group, upload cookbooks, install chef\n\ton all the nodes, sync share data and cookbooks."
	puts ""
	puts "\t\t$ rake create"

	puts ""
	puts "\t- List your currently running cloud server groups."
	puts ""
	puts "\t\t$ rake cloud:list"

	puts ""
	puts "\t- SSH into the current (most recently created) cloud server group"
	puts ""
	puts "\t\t$ rake ssh"

	puts ""
	puts "\t- SSH into a cloud server group with an ID of 3"
	puts ""
	puts "\t\t$ rake ssh GROUP_ID=3"

	puts ""
	puts "\t- Delete the cloud server group with an ID of 3"
	puts ""
	puts "\t\t$ rake cloud:delete GROUP_ID=3"

	puts ""
	puts "\t- Rebuild/Re-Chef a server in the most recently created cloud\n\tserver group"
	puts ""
	puts "\t\t$ rake rechef SERVER_NAME=db1"

	puts ""

end

task :default => 'usage'

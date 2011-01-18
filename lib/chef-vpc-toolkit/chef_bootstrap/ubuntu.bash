function install_chef {

CODENAME=$(cat /etc/*release | grep CODENAME | sed -e "s|^.*=\([^$]*\)$|\1|")
[[ "$CODENAME" == "maverick" ]] && CODENAME="lucid"
local INSTALL_TYPE=${1:-"CLIENT"} # CLIENT/SERVER

[ -f /etc/apt/sources.list.d/opscode.list ] || echo "deb http://apt.opscode.com $CODENAME main" > /etc/apt/sources.list.d/opscode.list
wget -q -O- http://apt.opscode.com/packages@opscode.com.gpg.key | apt-key add - &> /dev/null || { echo "Failed to configure Apt repo."; exit 1; }

dpkg -L rsync &> /dev/null || apt-get install -y rsync &> /dev/null

if ! dpkg -L chef &> /dev/null; then

	if [[ "$INSTALL_TYPE" == "SERVER" ]]; then

		[[ "$CODENAME" == "lucid" ]] || { echo "Ubuntu 10.0.4 lucid is required for Chef server installations."; exit 1; }
		apt-get update &> /dev/null || { echo "Failed to apt-get update."; exit 1; }
		echo "chef-solr    chef-solr/amqp_password    password  YA1B2C301234Z" | debconf-set-selections &> /dev/null || { echo "Failed to set debconf selections for chef-solr."; exit 1; }
		echo "chef    chef/chef_server_url    string  http://localhost:4000" | debconf-set-selections &> /dev/null || { echo "Failed to set debconf selections for chef."; exit 1; }
		DEBIAN_FRONTEND=noninteractive apt-get install -y chef-server chef &> /dev/null || { echo "Failed to install the Chef Server via apt-get on $HOSTNAME."; exit 1; }
	else
		apt-get update &> /dev/null || { echo "Failed to apt-get update."; exit 1; }
		echo "chef    chef/chef_server_url    string  http://localhost:4000" | debconf-set-selections &> /dev/null || { echo "Failed to set debconf selections for chef."; exit 1; }
		DEBIAN_FRONTEND=noninteractive apt-get install -y chef &> /dev/null || { echo "Failed to install Chef via apt-get on $HOSTNAME."; exit 1; }
	fi

	/etc/init.d/chef-client stop &> /dev/null
	sleep 2
	rm /var/log/chef/client.log

fi

}

function install_chef {

apt-get install -y lsb-release &> /dev/null || { echo "Failed to install lsb-release"; exit 1; }
CODENAME=$(/usr/bin/lsb_release -cs)
local INSTALL_TYPE=${1:-"CLIENT"} # CLIENT/SERVER

local CDN_BASE="http://c2521002.cdn.cloudfiles.rackspacecloud.com"
local TARBALL="chef-client-0.9.16-ubuntu.10.10-x86_64.tar.gz"

if [[ "$CODENAME" == "karmic" ]]; then
	# We install from APT, so no TARBALL required.
	echo "Using APT repo for Ubuntu 9.10"
elif [[ "$CODENAME" == "lucid" ]]; then
	if [[ "$INSTALL_TYPE" == "SERVER" ]]; then
		TARBALL="chef-server-0.9.16-ubuntu.10.04-x86_64.tar.gz"
	else
		TARBALL="chef-client-0.9.16-ubuntu.10.04-x86_64.tar.gz"
	fi
elif [[ "$CODENAME" == "maverick" || "$CODENAME" == "natty" || "$CODENAME" == "squeeze" ]]; then
	# XXX: Use the 10.10 build for 11.04 and Squeeze. Appears to work.
	if [[ "$INSTALL_TYPE" == "SERVER" ]]; then
		TARBALL="chef-server-0.9.16-ubuntu.10.10-x86_64.tar.gz"
	else
		TARBALL="chef-client-0.9.16-ubuntu.10.10-x86_64.tar.gz"
	fi
else
	echo "Only Ubuntu 9.10, 10.04, 10.10, 11.04 and Debian Squeeze are supported Chef clients."; exit 1;
fi

apt-get update &> /dev/null || { echo "Failed to apt-get update."; exit 1; }
dpkg -L rsync &> /dev/null || apt-get install -y rsync &> /dev/null


if ! dpkg -L chef &> /dev/null; then

	echo "chef-solr    chef-solr/amqp_password    password  YA1B2C301234Z" | debconf-set-selections &> /dev/null || { echo "Failed to set debconf selections for chef-solr."; exit 1; }
	echo "chef    chef/chef_server_url    string  http://localhost:4000" | debconf-set-selections &> /dev/null || { echo "Failed to set debconf selections for chef."; exit 1; }
	apt-get install -y ucf &> /dev/null || { echo "Failed to install ucf pkg"; exit 1; }

	if [[ "$CODENAME" == "karmic" ]]; then
		# Install from APT repo
		# See: http://www.opscode.com/blog/2010/07/01/new-apt-repository-for-chef-0-9/
		#

		cat >> /etc/apt/preferences <<EOF
Package: *chef*
Pin: version 0.9*
Pin-Priority: 1001
EOF

		echo >> /etc/apt/sources.list
		echo "deb http://apt.opscode.com/ karmic main" >> /etc/apt/sources.list

		wget -q -O- http://apt.opscode.com/packages@opscode.com.gpg.key | sudo apt-key add -

		apt-get update &> /dev/null || { echo "Failed to update"; exit 1; }

		apt-get install -y chef &> /dev/null || { echo "Could not install chef"; exit 1; }

	else
		local CHEF_PACKAGES_DIR=$(mktemp -d)

		wget "$CDN_BASE/$TARBALL" -O "$CHEF_PACKAGES_DIR/chef.tar.gz" &> /dev/null \
		    || { echo "Failed to download Chef RPM tarball."; exit 1; }
		cd $CHEF_PACKAGES_DIR
		tar xzf chef.tar.gz || { echo "Failed to extract Chef tarball."; exit 1; }
		rm chef.tar.gz

		DEBIAN_FRONTEND=noninteractive dpkg -i -R chef* &> /dev/null || { echo "Failed to install the Chef Server via apt-get on $HOSTNAME."; exit 1; }

		cd /tmp
		rm -Rf $CHEF_PACKAGES_DIR
	fi

	/etc/init.d/chef-client stop &> /dev/null
	sleep 2
	kill -9 $(pgrep chef-client) &> /dev/null || true
	rm /var/log/chef/client.log
fi

}

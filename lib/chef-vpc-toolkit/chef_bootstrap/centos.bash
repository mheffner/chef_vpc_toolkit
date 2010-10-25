function install_chef {

local INSTALL_TYPE=${1:-"CLIENT"} # CLIENT/SERVER

# cached RPMs from ELFF
local CDN_BASE="http://c2521002.cdn.cloudfiles.rackspacecloud.com"

local RH_RELEASE=$(cat /etc/redhat-release)
local TARBALL="chef-client-0.9.8-centos5.4-x86_64.tar.gz"

if [ "$RH_RELEASE" == "CentOS release 5.5 (Final)" ]; then
	TARBALL="chef-client-0.9.8-centos5.5-x86_64.tar.gz"
	if [[ "$INSTALL_TYPE" == "SERVER" ]]; then
		TARBALL="chef-server-0.9.8-centos5.5-x86_64.tar.gz"
	fi
else
	if [[ "$INSTALL_TYPE" == "SERVER" ]]; then
		TARBALL="chef-server-0.9.8-centos5.4-x86_64.tar.gz"
	fi
fi

rpm -q rsync &> /dev/null || yum install -y -q rsync
rpm -q wget &> /dev/null || yum install -y -q wget

if ! rpm -q rubygem-chef &> /dev/null; then

	local CHEF_RPM_DIR=$(mktemp -d)

	wget "$CDN_BASE/$TARBALL" -O "$CHEF_RPM_DIR/chef.tar.gz" &> /dev/null \
		|| { echo "Failed to download Chef RPM tarball."; exit 1; }
	cd $CHEF_RPM_DIR

	tar xzf chef.tar.gz || { echo "Failed to extract Chef tarball."; exit 1; }
	rm chef.tar.gz
	cd chef*
	yum install -q -y --nogpgcheck */*.rpm
	if [[ "$INSTALL_TYPE" == "SERVER" ]]; then
		rpm -q rubygem-chef-server &> /dev/null || { echo "Failed to install chef."; exit 1; }
	else
		rpm -q rubygem-chef &> /dev/null || { echo "Failed to install chef."; exit 1; }
	fi
	cd /tmp
	rm -Rf "$CHEF_RPM_DIR"

fi

}

# Installation functions for Chef 0.8 RPMs obtained from the ELFF repo.
export CHEF_STATUS_PORT="1234"
export STATUS_MONITOR_DIR="/root/status_monitor"

function configure_chef_server {

	echo ""

}

function print_client_validation_key {
	cat /etc/chef/validation.pem
}

function configure_chef_client {

if (( $# != 2 )); then
	echo "Unable to configure chef client."
	echo "usage: configure_chef_client <server_name> <client_validation_key>"
	exit 1
fi

local SERVER_NAME=$1
local CLIENT_VALIDATION_KEY=$2

if [ ! -f "/etc/chef/validation.pem" ]; then
	cat > /etc/chef/validation.pem <<-EOF_VALIDATION_PEM
$CLIENT_VALIDATION_KEY
	EOF_VALIDATION_PEM
	sed -e "/^$/d" -i /etc/chef/validation.pem
fi

local CLIENT_CONFIG="/etc/chef/client.rb"
local CHEF_NOTIFICATION_HANDLER=/var/lib/chef/handlers/netcat.rb
sed -e "s|localhost|$SERVER_NAME|g" -i $CLIENT_CONFIG
sed -e "s|^chef_server_url.*|chef_server_url \"http://$SERVER_NAME:4000\"|g" -i $CLIENT_CONFIG
sed -e "s|^log_location.*|log_location \"\/var/log/chef/client.log\"|g" -i $CLIENT_CONFIG
cat >> $CLIENT_CONFIG <<-EOF_CAT_CHEF_CLIENT_CONF
# custom Chef notification handler
require "$CHEF_NOTIFICATION_HANDLER"
netcat_handler = NetcatHandler.new
report_handlers << netcat_handler
exception_handlers << netcat_handler
EOF_CAT_CHEF_CLIENT_CONF


local CHEF_SYSCONFIG=/etc/default/chef-client
[ -d /etc/sysconfig/ ] && CHEF_SYSCONFIG=/etc/sysconfig/chef-client
cat > $CHEF_SYSCONFIG <<-"EOF_CAT_CHEF_SYSCONFIG"
INTERVAL=600
SPLAY=20
CONFIG=/etc/chef/client.rb
LOGFILE=/var/log/chef/client.log
EOF_CAT_CHEF_SYSCONFIG

mkdir -p /var/lib/chef/handlers
cat > $CHEF_NOTIFICATION_HANDLER <<-EOF_CHEF_NOTIFY
require 'socket'
class NetcatHandler < Chef::Handler
    def report
        begin
            socket = TCPSocket.open('$SERVER_NAME', $CHEF_STATUS_PORT)
            hostname=%x{hostname}.chomp
            if success?
                socket.write("#{hostname}:ONLINE\n")
            else
                socket.write("#{hostname}:FAILURE\n")
            end
            socket.close()
        rescue Exception => e
            Chef::Log.error("Netcat handler failed: " + e.message)
        end
    end
end
EOF_CHEF_NOTIFY

}

# This function will only run on the Chef Server for initial registration
function configure_knife {

local KNIFE_EDITOR=${1:-"vim"}

[ ! -f $HOME/.chef/chef-admin.pem ] || { echo "Knife already configured."; return 0; }

local COUNT=0
until [ -f /etc/chef/webui.pem ]; do
		echo "waiting for /etc/chef/webui.pem"
		sleep 1
		COUNT=$(( $COUNT + 1 ))
		if (( $COUNT > 30 )); then
				echo "timeout waiting for /etc/chef/webui.pem"
				exit 1
				break;
		fi
done
cd /tmp
/usr/bin/knife configure -i -s "http://localhost:4000" -u "chef-admin" -r "/root/cookbook-repos/chef-repo/" -y -d \
 || { echo "Failed to configure knife."; exit 1; }

cat > /etc/profile.d/knife.sh <<-EOF_CAT_KNIFE_SH
alias knife='EDITOR=$KNIFE_EDITOR knife'
EOF_CAT_KNIFE_SH

cat > /etc/profile.d/knife.csh <<-EOF_CAT_KNIFE_CSH
alias knife '/usr/bin/env EDITOR=$KNIFE_EDITOR knife'
EOF_CAT_KNIFE_CSH
chown root:root /etc/profile.d/knife*
chmod 755 /etc/profile.d/knife*

}

function knife_add_node {

if (( $# != 3 )); then
	echo "Unable to add node with knife."
	echo "usage: knife_add_node <node_name> <run_list> <json_attributes>"
	exit 1
fi

local NODE_NAME=$1
local RUN_LIST=$2
local ATTRIBUTES_JSON=$3

local DOMAIN_NAME=$(hostname -d)
local TMP_FILE=/tmp/node.json

cat > $TMP_FILE <<-EOF_CAT_CHEF_CLIENT_CONF
{
  "overrides": {

  },
  "name": "$NODE_NAME.$DOMAIN_NAME",
  "chef_type": "node",
  "json_class": "Chef::Node",
  "attributes": $ATTRIBUTES_JSON,
  "run_list": $RUN_LIST,
  "defaults": {

  }
}
EOF_CAT_CHEF_CLIENT_CONF

knife node from file $TMP_FILE 1> /dev/null || \
  { echo "Failed to add node with knife."; exit 1; }

rm $TMP_FILE

}

function knife_delete_node {

if (( $# != 1 )); then
	echo "Unable to add node with knife."
	echo "usage: knife_delete_node <node_name>"
	exit 1
fi

local NODE_NAME=$1
local DOMAIN_NAME=$(hostname -d)

knife node delete "$NODE_NAME.$DOMAIN_NAME" -y &> /dev/null || \
  { echo "Failed to delete node with knife. Ignoring..."; }
knife client delete "$NODE_NAME.$DOMAIN_NAME" -y &> /dev/null || \
  { echo "Failed to delete client with knife. Ignoring..."; }

    #delete any entries from the status.out file
	sed -e "/^$NODE_NAME:.*/d" -i $STATUS_MONITOR_DIR/status.out
}

function knife_create_databag {

if (( $# != 3 )); then
	echo "Unable to create databag with knife."
	echo "usage: knife_create_databag <bag_name> <item_id> <item_json>"
	exit 1
fi

local BAG_NAME=$1
local ITEM_ID=$2
local ITEM_JSON=$3

local TMP_FILE=/tmp/databag.json

cat > $TMP_FILE <<-EOF_CAT_CHEF_DATA_BAG
$ITEM_JSON
EOF_CAT_CHEF_DATA_BAG

knife data bag from file $BAG_NAME $TMP_FILE 1> /dev/null || \
  { echo "Failed to create data bag with knife."; exit 1; }

rm $TMP_FILE

}

function download_cookbook_repos {

local COOKBOOK_URLS=${1:?"Please specify a list of cookbook repos to download."}
local REPOS_BASEDIR=${2:-"/root/cookbook-repos"}

# download and extract the cookbooks
for CB_REPO in $COOKBOOK_URLS; do
echo -n "Downloading $CB_REPO..."
	if [ "http:" == ${CB_REPO:0:5} ] || [ "https:" == ${CB_REPO:0:6} ]; then
		wget --no-check-certificate "$CB_REPO" -O "/tmp/cookbook-repo.tar.gz" &> /dev/null || { echo "Failed to download cookbook tarball."; return 1; }
	else
		download_cloud_file "$CB_REPO" "/tmp/cookbook-repo.tar.gz"
	fi
echo "OK"
cd $REPOS_BASEDIR
echo -n "Extracting $CB_REPO..."
tar xzf /tmp/cookbook-repo.tar.gz
rm /tmp/cookbook-repo.tar.gz
echo "OK"
done

}

function knife_upload_cookbooks_and_roles {

local REPOS_BASEDIR=${1:-"/root/cookbook-repos"}

# install cookbooks
local REPOS=""
for CB_REPO in $(ls $REPOS_BASEDIR); do
[ -n "$REPOS" ] && REPOS="$REPOS,"
REPOS="$REPOS'$REPOS_BASEDIR/$CB_REPO/cookbooks', '$REPOS_BASEDIR/$CB_REPO/site-cookbooks'"
done
sed -e "s|^cookbook_path.*|cookbook_path [ $REPOS ]|" -i $HOME/.chef/knife.rb
/usr/bin/knife cookbook metadata -a &> /dev/null || { echo "Failed to generate cookbook metadata."; exit 1; }
/usr/bin/knife cookbook upload -a &> /dev/null || { echo "Failed to install cookbooks."; exit 1; }

# install roles
for CB_REPO in $(ls $REPOS_BASEDIR); do
    for ROLE in $(ls $REPOS_BASEDIR/$CB_REPO/roles/); do
        [[ "$ROLE" == "README" ]] || \
            /usr/bin/knife role from file "$REPOS_BASEDIR/$CB_REPO/roles/$ROLE" 1> /dev/null
    done
done

}

function start_chef_server {

	# Ubuntu starts the Chef server automatically
	if [ -f /bin/rpm ]; then
		/sbin/service couchdb start 1> /dev/null
		/sbin/chkconfig couchdb on
		/sbin/service rabbitmq-server start </dev/null &> /dev/null
		/sbin/chkconfig rabbitmq-server on

		for svc in chef-solr chef-solr-indexer chef-server chef-server-webui
		do
			/sbin/service $svc start
			/sbin/chkconfig $svc on
		done
	fi

}

function start_chef_client {

	/etc/init.d/chef-client start
    if [ -f /sbin/chkconfig ]; then
		chkconfig chef-client on
	fi

}


function start_notification_server {


[ -d "$STATUS_MONITOR_DIR" ] && return 0;

if [ -f /usr/bin/yum ]; then
    rpm -q nc &> /dev/null || yum install -y -q nc
elif [ -f /usr/bin/dpkg ]; then
    dpkg -L netcat-openbsd > /dev/null 2>&1 || apt-get install -y --quiet netcat-openbsd > /dev/null 2>&1
else
    echo "Failed to install netcat. (for Chef status monitoring)"
    exit 1
fi

mkdir -p $STATUS_MONITOR_DIR
cat >> $STATUS_MONITOR_DIR/server.sh <<-EOF_NC_NOTIFY_SERVER
#!/bin/bash
while true; do
nc -l $CHEF_STATUS_PORT >> $STATUS_MONITOR_DIR/status.out
done
EOF_NC_NOTIFY_SERVER
bash $STATUS_MONITOR_DIR/server.sh &> /dev/null < /dev/null &

}

function poll_chef_client_online {

local CLIENT_NAMES=${1:?"Please specify a chef client name."}
local SECS=${2:-"600"} #10 minutes

local SLEEP_COUNT=5
local COUNT=1
local MAX_COUNT=$(( $SECS / $SLEEP_COUNT ))
local FAILED_CLIENTS=""
local ALL_ONLINE="true"
until (( $COUNT == $MAX_COUNT )); do
    ALL_ONLINE="true"
    FAILED_CLIENTS=""
    for NAME in $CLIENT_NAMES; do
            if ! grep "$NAME:" $STATUS_MONITOR_DIR/status.out | tail -n 1 | grep -c ":ONLINE" &> /dev/null; then
                ALL_ONLINE="false"
                FAILED_CLIENTS="$NAME $FAILED_CLIENTS"
            fi
    done
    if [[ $ALL_ONLINE == "true" ]]; then
        echo "All Chef client(s) ran successfully."
        return 0
    fi
    COUNT=$(( $COUNT + 1 ))
    sleep $SLEEP_COUNT
done

echo "Chef client(s) failed to run: $FAILED_CLIENTS"
return 1

}

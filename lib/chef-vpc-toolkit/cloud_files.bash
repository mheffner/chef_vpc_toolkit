# Load the username and password into variables that are used by this
# bash API.
function install_curl {

if [ -f /usr/bin/yum ]; then
	rpm -q curl &> /dev/null || yum install -y -q curl
elif [ -f /usr/bin/dpkg ]; then
	dpkg -L curl > /dev/null 2>&1 || apt-get install -y --quiet curl > /dev/null 2>&1
else
	echo "Failed to install curl. Unsupported platform."
	exit 1
fi

}

function load_cloud_configs {

	if [ -z "$RACKSPACE_CLOUD_API_USERNAME" ] || [ -z "$RACKSPACE_CLOUD_API_KEY" ]; then

		if [ ! -f ~/.rackspace_cloud ]; then
			echo "Missing .rackspace_cloud config file."
			exit 1
		fi

		export RACKSPACE_CLOUD_API_USERNAME=$(cat ~/.rackspace_cloud | grep "userid" | sed -e "s|.*: \([^ \n\r]*\).*|\1|")
		export RACKSPACE_CLOUD_API_KEY=$(cat ~/.rackspace_cloud | grep "api_key" | sed -e "s|.*: \([^ \n\r]*\).*|\1|")

		if [ -z "$RACKSPACE_CLOUD_API_USERNAME" ] || [ -z "$RACKSPACE_CLOUD_API_KEY" ]; then
			echo "Please define a 'userid' and 'api_key' in ~/.rackspace_cloud"
			exit 1
		fi

	fi

}

# Download a private file from Rackspace Cloud Files using the secure
# X-Storage-Url.
function download_cloud_file {

	if (( $# != 2 )); then
		echo "Failed to download cloud file."
		echo "usage: download_cloud_file <container_url> <output_file>"
		exit 1
	fi

	load_cloud_configs
	install_curl

	local CONTAINER_URL=$1
	local OUTPUT_FILE=$2

	local AUTH_RESPONSE=$(curl -D - \
		-H "X-Auth-Key: $RACKSPACE_CLOUD_API_KEY" \
		-H "X-Auth-User: $RACKSPACE_CLOUD_API_USERNAME" \
		"https://auth.api.rackspacecloud.com/v1.0" 2> /dev/null)

	[[ $? == 0 ]] || { echo "Failed to authenticate."; exit 1; }

	local AUTH_TOKEN=$(echo $AUTH_RESPONSE | \
		sed -e "s|.* X-Auth-Token: \([^ \n\r]*\).*|\1|g")
	local STORAGE_URL=$(echo $AUTH_RESPONSE | \
		sed -e "s|.* X-Storage-Url: \([^ \n\r]*\).*|\1|g")

	curl -s -X GET -H "X-Auth-Token: $AUTH_TOKEN" "$STORAGE_URL/$CONTAINER_URL" -o "$OUTPUT_FILE"

}

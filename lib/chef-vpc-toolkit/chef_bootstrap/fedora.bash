function install_chef {

local INSTALL_TYPE=${1:-"CLIENT"} # CLIENT/SERVER

	[[ "$INSTALL_TYPE" == "CLIENT" ]] || { echo "Chef server installations are not yet supported on Fedora."; exit 1; }

	yum install -q -y ruby ruby-devel gcc gcc-c++ automake autoconf rubygems make &> /dev/null || { echo "Failed to install ruby, ruby-devel, etc."; exit 1; }
	gem update --system
	gem update
	gem install json -v 1.1.4 --no-rdoc --no-ri &> /dev/null || \
		{ echo "Failed to install JSON gem on $HOSTNAME."; exit 1; }
	gem install ohai -v 0.5.6 --no-rdoc --no-ri &> /dev/null || \
		{ echo "Failed to install ohai gem on $HOSTNAME."; exit 1; }
	gem install chef -v 0.9.8 --no-rdoc --no-ri &> /dev/null || \
		{ echo "Failed to install chef gem on $HOSTNAME."; exit 1; }

	for DIR in /etc/chef /var/log/chef /var/cache/chef /var/lib/chef /var/run/chef; do
		mkdir -p $DIR
	done

	cat > /etc/chef/client.rb <<-"EOF_CAT"
log_level          :info
log_location       STDOUT
ssl_verify_mode    :verify_none
chef_server_url "http://localhost:4000"
file_cache_path    "/var/cache/chef"
file_backup_path   "/var/lib/chef/backup"
pid_file           "/var/run/chef/client.pid"
cache_options({ :path => "/var/cache/chef/checksums", :skip_expires => true})
signing_ca_user "chef"
Mixlib::Log::Formatter.show_time = true
validation_client_name "chef-validator"
validation_key         "/etc/chef/validation.pem"
client_key             "/etc/chef/client.pem"
EOF_CAT

	cp /usr/lib/ruby/gems/1.8/gems/chef-0.9.8/distro/redhat/etc/init.d/chef-client /etc/init.d/
	cp /usr/lib/ruby/gems/1.8/gems/chef-0.9.8/distro/redhat/etc/logrotate.d/chef-client /etc/logrotate.d/
	chmod 755 /etc/init.d/chef-client

}

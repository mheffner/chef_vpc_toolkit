
module ChefVPCToolkit
class VpnConnection

       	CERT_DIR=File.join(ENV['HOME'], '.pki', 'openvpn')

        def initialize(group, client)
                @group = group
                @client = client
        end

        def connect
                # XXX: abstract

                @ca_cert=get_cfile('ca.crt')
                @client_cert=get_cfile('client.crt')
		@client_key=get_cfile('client.key')

		vpn_interface = @client.vpn_network_interfaces[0]

		FileUtils.mkdir_p(File.join(CERT_DIR, @group.id.to_s))
		File::chmod(0700, File.join(ENV['HOME'], '.pki'))
		File::chmod(0700, CERT_DIR)

		File.open(@ca_cert, 'w') { |f| f.write(vpn_interface.ca_cert) }
		File.open(@client_cert, 'w') { |f| f.write(vpn_interface.client_cert) }
		File.open(@client_key, 'w') do |f|
			f.write(vpn_interface.client_key)
			f.chmod(0600)
		end

                @up_script=get_cfile('up.bash')
                File.open(@up_script, 'w') do |f|
                        f << <<EOF_UP
#!/bin/bash

# setup routes
/sbin/route add #{@group.vpn_network.chomp("0")+"1"} dev \$dev
/sbin/route add -net #{@group.vpn_network} netmask 255.255.128.0 gw #{@group.vpn_network.chomp("0")+"1"}

mv /etc/resolv.conf /etc/resolv.conf.bak
egrep ^search /etc/resolv.conf.bak | sed -e 's/search /search #{@group.domain_name} /' > /etc/resolv.conf
echo 'nameserver #{@group.vpn_network.chomp("0")+"1"}' >> /etc/resolv.conf
grep ^nameserver /etc/resolv.conf.bak >> /etc/resolv.conf
EOF_UP
                        f.chmod(0700)
                end
                @down_script=get_cfile('down.bash')
                File.open(@down_script, 'w') do |f|
                        f << <<EOF_DOWN
#!/bin/bash
mv /etc/resolv.conf.bak /etc/resolv.conf
EOF_DOWN
                        f.chmod(0700)
                end

                @config_file=get_cfile('config')
                File.open(@config_file, 'w') do |f|
                        f << <<EOF_CONFIG
client
dev tun
proto tcp

#Change my.publicdomain.com to your public domain or IP address
remote #{@group.vpn_gateway} 1194

resolv-retry infinite
nobind
persist-key
persist-tun

script-security 2

ca #{@ca_cert}
cert #{@client_cert}
key #{@client_key}

ns-cert-type server

route-nopull

comp-lzo

verb 3
up #{@up_script}
down #{@down_script}
EOF_CONFIG
                        f.chmod(0600)
                end

                system("sudo openvpn --config #{@config_file} --writepid #{get_cfile('openvpn.pid')} --daemon")
        end

        def disconnect
                raise "Not running? No pid file found!" unless File.exist?(get_cfile('openvpn.pid'))
                pid = File.read(get_cfile('openvpn.pid')).chomp
                system("sudo kill -TERM #{pid}")
        end

        def clean
		FileUtils.rm_rf(File.join(CERT_DIR, @group.id.to_s))
	end
private

        def get_cfile(file)
                File.join(CERT_DIR, @group.id.to_s, file)
        end
end
end

#!/bin/bash
# Setting wireguard client on openWRT 
# Filtering by domain names
# Для работы скрипта необходим конфигурационный файл сгенерированный wireguard_server.sh
# Конфигурационный файл поместить в одну деректорию с данным скриптом

#----------VARIABLES----------

CONFIG_FILE=""
PRIVATE_KEY=""
WGS_PORT=""
WG_IP=""
PUBLIC_KEY=""
HOST=""

loop=1
OPENWRT_RELEASE=$(cat /etc/openwrt_release | awk 'BEGIN{FS="="} /DISTRIB_RELEASE/{print $2}' | cut -c 2- | awk 'BEGIN{FS="."} {print $1} END{sub(/^.{2}/,"")}')

#----------FUNCTIONS----------

# create menu for selection 
function menu {
	local arr=($1)
	local message=$2
	
	while [ $loop -gt 0 ]
	do
		local i=1
		for item in ${arr[@]}
		do
			message+="$i. $item\n"
			i=$(($i + 1))
		done

		message+="\n"
		printf "${message}"

		read -p "Enter selection [1-${#arr[@]}] > "

		if [[ "$REPLY" =~ ^[1-${#arr[@]}]$ ]]; then
			menuResult="${arr[$(($REPLY - 1))]}"
			loop=0
		else
			echo "Your selection is not correct. Let's try again."
			message=$2
		fi
	done

	loop=1
}

#----------ACTIONS----------

if [ $(ls -1 *.conf  2>/dev/null | wc -l) = 0 ];then
	echo "Attention, you need to place a file configuration into directory this script, and restart this script"
else
	menu "$(ls *.conf)" "Plase choose the configuration file:\n\n"
	CONFIG_FILE=$menuResult

	PRIVATE_KEY=$(sudo awk 'BEGIN{FS=" = "} /PrivateKey/{print $2}' $CONFIG_FILE)
	WGS_PORT=$(sudo awk 'BEGIN{FS=" = "} /Endpoint/{print $2}' $CONFIG_FILE | sudo awk 'BEGIN{FS=":"} {print $2}')
	WG_IP=$(sudo awk 'BEGIN{FS=" = "} /Address/{print $2}' $CONFIG_FILE)

	PUBLIC_KEY=$(sudo awk 'BEGIN{FS=" = "} /PublicKey/{print $2}' $CONFIG_FILE)
	HOST=$(sudo awk 'BEGIN{FS=" = "} /Endpoint/{print $2}' $CONFIG_FILE | sudo awk 'BEGIN{FS=":"} {print $1}')

	# update packets
	opkg update
	opkg list-upgradable | cut -f 1 -d ' ' | xargs -r opkg upgrade

	# installation wireguard
	opkg update && opkg install wireguard-tools

	# setting wireguard client on openWRT
	# setting network
	uci delete network.wg0
	uci set network.wg0="interface"
	uci set network.wg0.proto="wireguard"
	uci set network.wg0.private_key="$PRIVATE_KEY"
	uci set network.wg0.listen_port="$WGS_PORT"
	uci add_list network.wg0.addresses="$WG_IP"
	
	uci delete network.peer.wireguard_wg0
	uci set network.peer="wireguard_wg0"
	uci set network.peer.public_key="$PUBLIC_KEY"
	uci set network.peer.endpoint_host="$HOST"
	uci set network.peer.endpoint_port="$WGS_PORT"
	uci set network.peer.route_allowed_ips="0"
	uci set network.peer.persistent_keepalive="25"
	uci set network.peer.allowed_ips="0.0.0.0/0"

	uci commit network
	service network restart

	# setting firewall
	uci delete firewall.zone.wg
	uci add firewall zone
	uci set firewall.@zone[-1]=zone
	uci set firewall.@zone[-1].name='wg'
	uci set firewall.@zone[-1].masq='1'
	uci set firewall.@zone[-1].output='ACCEPT'
	uci set firewall.@zone[-1].forward='REJECT'
	uci set firewall.@zone[-1].input='REJECT'
	uci set firewall.@zone[-1].mtu_fix='1'
	uci set firewall.@zone[-1].network='wg0'

	uci add firewall forwarding
	uci set firewall.@forwarding[-1]=forwarding
	uci set firewall.@forwarding[-1].src='lan'
	uci set firewall.@forwarding[-1].dest='wg'

	# install dnsmasq-full
	opkg update && cd /tmp/ && opkg download dnsmasq-full
	opkg remove dnsmasq && opkg install dnsmasq-full --cache /tmp/
	mv /etc/config/dhcp-opkg /etc/config/dhcp

	# install curl
	opkg install curl

	# create routing table
	echo '99 vpn' >> /etc/iproute2/rt_tables

	# make a rule for trafic
	uci delete network.rule.mark0x1
	uci add network rule
	uci set network.@rule[-1].name='mark0x1'
	uci set network.@rule[-1].mark='0x1'
	uci set network.@rule[-1].priority='100'
	uci set network.@rule[-1].lookup='vpn'
	uci commit network

	# make a rule for routing table
	uci delete network.rule.wg0
	uci set network.vpn_route=route
	uci set network.vpn_route.interface='wg0'
	uci set network.vpn_route.table='vpn'
	uci set network.vpn_route.target='0.0.0.0/0'
	uci commit network

	# crate ip's list
	uci delete firewall.ipset.vpn_domains
	uci add firewall ipset
	uci set firewall.@ipset[-1].name='vpn_domains'
	uci set firewall.@ipset[-1].match='dst_net'

	# create rule for mark trafic
	uci delete firewall.rule.mark_domains
	uci add firewall rule
	uci set firewall.@rule[-1]=rule
	uci set firewall.@rule[-1].name='mark_domains'
	uci set firewall.@rule[-1].src='lan'
	uci set firewall.@rule[-1].dest='*'
	uci set firewall.@rule[-1].proto='all'
	uci set firewall.@rule[-1].ipset='vpn_domains'
	uci set firewall.@rule[-1].set_mark='0x1'
	uci set firewall.@rule[-1].target='MARK'
	uci set firewall.@rule[-1].family='ipv4'
	uci commit firewall

	cp getdomain_openwrt$OPENWRT_RELEASE /etc/init.d/getdomains

	chmod +x /etc/init.d/getdomains
	ln -sf ../init.d/getdomains /etc/rc.d/S99getdomains

	echo "0 */8 * * * /etc/init.d/getdomains start" >> /etc/crontabs/root
	/etc/init.d/cron enable
	/etc/init.d/cron start

	service network restart
	service getdomains start
fi
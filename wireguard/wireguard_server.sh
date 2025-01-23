#!/bin/bash
# Install and setting wireguard on a remote server

#----------VARIABLES----------

HOSTNAME=$hostname

#----------FUNCTIONS----------

# get array of interface
function getInterface {
	local arr=()
	for iface in $(ifconfig | cut -d ' ' -f1 | tr ':' '\n' | awk NF)
	do
		arr+=("$iface")
	done

	echo ${arr[@]}
}

# create menu for selection 
function menu {
	local arr=($1)
	local message+="$2"
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
	else
		echo "Your selection is not correct"
	fi
}

# write to file ($1= string, $2= path file)
function write {
		local string=$1
		local path=$2

		echo -e $string | sudo tee -a $path
}

# get some information from user ($1= message)
function getInfo {
	read -p "$1: "
	infoResult="$REPLY"
}

# add peer to wg-server.conf file ($1 = peer's name, $2 = ordinal number of peer, $3 = wireguard's ip, $4 = server's public key, $5 = server's ip, $6 = a listaning port)
function addPeer {
	#  add peer to wg-server.conf file
	local name=$1
	local number=$2
	local wgip=$3
	local server_pubkey=$4
	local server_ip=$5
	local port=$6

	sudo wg genkey | sudo tee /etc/wireguard/cliemts_key/${name}_privatekey | sudo wg pubkey | sudo tee /etc/wireguard/cliemts_key/${name}_publickey
	local key=$(cat /etc/wireguard/cliemts_key/${name}_privatekey)
	local pubkey=$(cat /etc/wireguard/cliemts_key/${name}_publickey)
	local peer="#${name}\n[Peer]\nPublicKey = ${pubkey}\nAllowedIPs = ${wgip%.*}.${number}/32"

	write "${peer}" "/etc/wireguard/wg-server.conf"

	# create a file <peer's name>.conf
	sudo touch /etc/wireguard/clients_key/${name}.conf

	local client="[Interface]\nPrivateKey = ${key}\nAddress = ${wgip%.*}.${number}/32\nDNS = 8.8.8.8\n\n[Peer]\nPublicKey = ${server_pubkey}\nEndpoint = ${server_ip}:${port}\nAllowedIPs = 0.0.0.0/0\nPersistentKeepalive = 20\n"

	write "${client}" "/etc/wireguard/cliemts_key/${name}.conf"
}

#----------ACTIONS----------

# get a list of interface and display a selection menu
menu "$(getInterface)" "Plase choose the interface:\n\n"
# assign the result of the interface selection to the variable INTERFACE
INTERFACE=$menuResult

# get server's ip address
SERVER_IP=$(ifconfig | awk -v var="$INTERFACE" 'BEGIN{RS=""} match($0, var)' | awk '/inet /{print $2}')

echo "SERVER_IP = $SERVER_IP"



sudo mkdir /etc/wireguard
sudo mkdir /etc/wireguard/cliemts_key

# generate server key
sudo wg genkey | sudo tee /etc/wireguard/privatekey | sudo wg pubkey | sudo tee /etc/wireguard/publickey
WGS_KEY=$(sudo cat /etc/wireguard/privatekey)
# permit to the privatekey
sudo chmod 600 /etc/wireguard/privatekey
WGS_PUB=$(sudo cat /etc/wireguard/publickey)

# assign a wireguard port
getInfo "Type a port number. Be sure this port is not used an another app"
WGS_PORT=$infoResult

sudo iptables -I INPUT -p udp -m udp --dport $WGS_PORT -j ACCEPT # open port in firewall
sudo netfilter-persistent save # save iptables

# assign a wg ip address 
getInfo "Type an ip address wireguard network"
WG_ADDR=$infoResult

# create the config file wg-server.conf
sudo touch /etc/wireguard/wg-server..conf
sudo chmod 600 /etc/wireguard/wg-server..conf

WGS_INTERFACE="[Interface]\nPrivateKey = ${WGS_KEY}\nAddress = ${WG_ADDR%.*}.1/24\nListenPort = ${WGS_PORT}\nPostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${INTERFACE} -j MASQUERADE\nPostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE\n"

write "${WGS_INTERFACE}" "/etc/wireguard/wg-server.conf"

# ip forwarding
sudo echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# start systemd demon of wireguard
sudo systemctl enable wg-quick@wg-server.service
sudo systemctl start wg-quick@wg-server.service

#sudo systemctl status wg-quick@wg-server.service

# assign the number of clients
getInfo "How many clients do you need?"
CLIENTS_COUNT=$infoResult

# create peers
for (( i=0; i < CLIENTS_COUNT; i++ ))
do
	getInfo "Type $(( i + 1 )) peer's name"
	addPeer $infoResult $(( i + 2 )) $WG_ADDR $WGS_PUB $SERVER_IP $WGS_PORT
done

sudo systemctl restart wg-quick@wg-server.service
sudo wg show

echo -e "\nДля скачивания файлов конфигурации используйте команду:\n\tscp -rO tsebom@${SERVER_IP}:/etc/wireguard/cliemts_key/ ~/${HOSTNAME}/"
#!/bin/bash
# Install and setting wireguard on a remote server

#----------VARIABLES----------

HOSTNAME=$hostname # Hostname
INTERFACE="" # server's interface
SERVER_IP="" # ip address server
WGS_KEY="" # server's private key 
WGS_PUB="" # server's public key
WGS_PORT="" # port is listened on by wg server
WG_ADDR="" # ip address wireguard's network
CONFIG_FILE="" # config file's name

flag="server"
loop=1

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
	local message=$2
	
	while [ $loop -gt 0 ]
	local i=1
	do
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

# add peer to <wg-server>.conf file ($1 = peer's name, $2 = ordinal number of peer, $3 = wireguard's ip, $4 = server's public key, $5 = server's ip, $6 = a listaning port, $7 = configuration file name)
function addPeer {
	local name=$1
	local number=$2
	local wgip=$3
	local server_pubkey=$4
	local server_ip=$5
	local port=$6
	local serv_conf=$7

	sudo wg genkey | sudo tee /etc/wireguard/cliemts_key/${name}_privatekey | sudo wg pubkey | sudo tee /etc/wireguard/cliemts_key/${name}_publickey
	local key=$(cat /etc/wireguard/cliemts_key/${name}_privatekey)
	sudo rm /etc/wireguard/cliemts_key/${name}_privatekey
	local pubkey=$(cat /etc/wireguard/cliemts_key/${name}_publickey)
	local peer="#${name}\n[Peer]\nPublicKey = ${pubkey}\nAllowedIPs = ${wgip%.*}.${number}/32"

	write "${peer}" "/etc/wireguard/${serv_conf}.conf"

	# create a file <peer's name>.conf
	sudo touch /etc/wireguard/clients_conf/${name}.conf

	local client="[Interface]\nPrivateKey = ${key}\nAddress = ${wgip%.*}.${number}/32\nDNS = 8.8.8.8\n\n[Peer]\nPublicKey = ${server_pubkey}\nEndpoint = ${server_ip}:${port}\nAllowedIPs = 0.0.0.0/0\nPersistentKeepalive = 20\n"

	write "${client}" "/etc/wireguard/cliemts_conf/${name}.conf"
}

#----------ACTIONS----------

# get a list of interface and display a selection menu
menu "$(getInterface)" "Plase choose the interface:\n\n"
# assign the result of the interface selection to the variable INTERFACE
INTERFACE=$menuResult

# get server's ip address
SERVER_IP=$(ifconfig | awk -v var="$INTERFACE" 'BEGIN{RS=""} match($0, var)' | awk '/inet /{print $2}')
echo "SERVER_IP = $SERVER_IP"

if [ ! -d "/etc/wireguard" ]; then 
	# create directories for wireguard
	sudo mkdir /etc/wireguard
	sudo mkdir /etc/wireguard/cliemts_key
	sudo mkdir /etc/wireguard/cliemts_conf
fi

# assign value for flag variable
menu "server peer" "What do you need to add?\n\n"
flag=$menuResult

# Cheek which configuration files are in '/etc/wireguard/'
if [ $(ls -1 /etc/wireguard/*.conf 2>/dev/null | wc -l) != 0 ]
then 
	echo -e "Diretory '/etc/wireguard/' have these configuration files:"
	sudo ls -1 /etc/wireguard/*.conf | awk 'BEGIN{FS="/"} {print $NF}' 
	echo -e "\n"
fi

# assign a name for configuration file for setting
read -p "Type the name of wireguard configuration file whithout extention: "
CONFIG_FILE=$REPLY

# ..................SERVER..................

if [ $flag="server" ]; then
	
	sudo touch /etc/wireguard/$CONFIG_FILE.conf
	sudo chmod 600 /etc/wireguard/$CONFIG_FILE.conf

	# generate server key
	sudo wg genkey | sudo tee /etc/wireguard/$CONFIG_FILE-privatekey | sudo wg pubkey | sudo tee /etc/wireguard/$CONFIG_FILE-publickey
	WGS_KEY=$(sudo cat /etc/wireguard/$CONFIG_FILE-privatekey)
	# permit to the privatekey
	sudo chmod 600 /etc/wireguard/$CONFIG_FILE-privatekey
	WGS_PUB=$(sudo cat /etc/wireguard/$CONFIG_FILE-publickey)

	# assign a wireguard port
	getInfo "Type a port number. Be sure this port is not used an another app"
	WGS_PORT=$infoResult
	sudo iptables -I INPUT -p udp -m udp --dport $WGS_PORT -j ACCEPT # open port in firewall
	sudo netfilter-persistent save # save iptables

	# assign a wg ip address 
	getInfo "Type an ip address wireguard network"
	WG_ADDR=$infoResult

	# write server configuration in the <wg-server>conf
	server_intrface="[Interface]\nPrivateKey = ${WGS_KEY}\nAddress = ${WG_ADDR%.*}.1/24\nListenPort = ${WGS_PORT}\nPostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${INTERFACE} -j MASQUERADE\nPostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE\n"
	write "${server_intrface}" "/etc/wireguard/$CONFIG_FILE.conf"

	# ip forwarding
	sudo echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

	# start systemd demon of wireguard
	sudo systemctl enable wg-quick@$CONFIG_FILE.service
	sudo systemctl start wg-quick@$CONFIG_FILE.service
	#sudo systemctl status wg-quick@$CONFIG_FILE.service

	flag="peer"
fi

# ...................PEER...................

if [ $flag="peer" ]; then

WG_ADDR=$(sudo awk 'BEGIN{FS=" = "} /Address/{print $2}' /etc/wireguard/$CONFIG_FILE.conf)
WGS_PUB=$(sudo cat /etc/wireguard/$CONFIG_FILE-publickey)
WGS_PORT=$(sudo awk 'BEGIN{FS=" = "} /ListenPort/{print $2}' /etc/wireguard/$CONFIG_FILE.conf)

	while [ $loop -gt 0]
	do
		local i=$(sudo awk 'BEGIN{peer=0} /Peer/{peer++} END{print peer}' /etc/wireguard/$CONFIG_FILE.conf)
		getInfo "Type peer's name"
		addPeer $infoResult $(( i + 2 )) $WG_ADDR $WGS_PUB $SERVER_IP $WGS_PORT $CONFIG_FILE

		menu "yes no" "Do you want to add another peer?"
		if [ $menuResult="no" ]; then
			loop=1
		fi
	done
fi

sudo systemctl restart wg-quick@$CONFIG_FILE.service
sudo wg show

echo -e "\nДля скачивания файлов конфигурации используйте команду:\n\tscp -rO tsebom@${SERVER_IP}:/etc/wireguard/cliemts_conf/ ~/${HOSTNAME}/"

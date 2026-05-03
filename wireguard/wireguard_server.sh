#!/bin/bash
# Install and setting wireguard on a remote server for using chatGPT

#----------VARIABLES----------

RED='\033[0;31m' # ANSI код для красного
GREEN='\033[0;32m' # ANSI код для зеленого
NC='\033[0m' # Сброс цвета (No Color)

INTERFACE="" # server's interface
SERVER_IP="" # ip address server
WGS_KEY="" # server's private key 
WGS_PUB="" # server's public key
WGS_PORT="" # port is listened on by wg server
WG_ADDR="" # ip address wireguard's network
CONFIG_FILE="" # config file's name

MY_USER=${SUDO_USER:-$(logname)}
flag="server"
loop=1

#----------FUNCTIONS----------

# get array of interface
function getInterface {
	local arr=()
	for iface in $(ip -o link show | awk -F': ' '{print $2}')
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
	do
		local display_msg="$message\n"
		local i=1
		for item in "${arr[@]}";
		do
			display_msg+="$i. $item\n"
			i=$(($i + 1))
		done

		display_msg+="\n"
		printf "%b" "${display_msg}"

		read -p "Enter selection [1-${#arr[@]}] > "

		if [[ "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#arr[@]} )); then
			menuResult="${arr[$(($REPLY - 1))]}"
			loop=0
		else
			echo "${RED}Warning: Your selection is not correct. Let's try again.${NC}"
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
	local input
	while true; do
		read -p "$1: " input
		if [[ -n "$input" ]]; then
			infoResult="$input"
			break
		else
			echo "${RED}Warning: Field cannot be empty. Repeat your entry.${NC}"
		fi
	done
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

	local key=$(sudo wg genkey)
	local pubkey=$(echo "$key" | sudo wg pubkey)

	local peer="#${name}\n[Peer]\nPublicKey = ${pubkey}\nAllowedIPs = ${wgip%.*}.${number}/32"
	write "${peer}" "/etc/wireguard/${serv_conf}.conf"

	# create a file <peer's name>.conf
	sudo touch /etc/wireguard/clients_conf/${name}.conf
	sudo chmod 600 "/etc/wireguard/clients_conf/${name}.conf"

	local client="[Interface]\nPrivateKey = ${key}\nAddress = ${wgip%.*}.${number}/32\nDNS = 8.8.8.8\n\n[Peer]\nPublicKey = ${server_pubkey}\nEndpoint = ${server_ip}:${port}\nAllowedIPs = 0.0.0.0/0\nPersistentKeepalive = 20\n"
	write "${client}" "/etc/wireguard/clients_conf/${name}.conf"

	unset key
	unset pubkey

	if command -v qrencode &> /dev/null; then
		qrencode -o /etc/wireguard/clients_conf/${name}.png -r /etc/wireguard/clients_conf/${name}.conf
	fi
}

#----------ACTIONS----------

# get a list of interface and display a selection menu
menu "$(getInterface)" "Please choose the interface:\n\n"
# assign the result of the interface selection to the variable INTERFACE
INTERFACE=$menuResult

# get server's ip address
SERVER_IP=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "SERVER_IP = $SERVER_IP"

if [ ! -d "/etc/wireguard" ]; then 
	# create directories for wireguard
	sudo mkdir /etc/wireguard
	sudo mkdir /etc/wireguard/clients_conf
else
	if [ ! -d "/etc/wireguard/clients_conf" ]; then
		sudo mkdir /etc/wireguard/clients_conf
	fi
fi

# assign value for flag variable
menu "server peer" "What do you need to add?\n\n"
flag=$menuResult

# Check which configuration files are in '/etc/wireguard/'
if [ $(ls -1 /etc/wireguard/*.conf 2>/dev/null | wc -l) != 0 ]
then 
	echo -e "Diretory '/etc/wireguard/' have these configuration files:"
	sudo ls -1 /etc/wireguard/*.conf | awk 'BEGIN{FS="/"} {print $NF}' 
	echo -e "\n"
fi

while true
do
	# assign a name for configuration file for setting
	read -p "Type the name of wireguard configuration file without extention: " CONFIG_FILE

	if [[ ! "$CONFIG_FILE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
		echo -e "${RED}Warning: Invalid file name. Use only letters, numbers, dashes (-) and underscores (_).${NC}"
	else
		break
	fi
done

# ..................SERVER..................

if [ $flag = "server" ]; then
	
	sudo touch /etc/wireguard/$CONFIG_FILE.conf
	sudo chmod 600 /etc/wireguard/$CONFIG_FILE.conf

	WGS_KEY_PATH=/etc/wireguard/$CONFIG_FILE-privatekey
	WGS_PUB_PATH=/etc/wireguard/$CONFIG_FILE-publickey

	# generate server key
	sudo wg genkey | sudo tee $WGS_KEY_PATH | sudo wg pubkey | sudo tee $WGS_PUB_PATH
	sudo chmod 600 $WGS_KEY_PATH

	WGS_KEY=$(sudo cat $WGS_KEY_PATH)
	WGS_PUB=$(sudo cat $WGS_PUB_PATH)

	# assign a wireguard port
	while true; do
		# Prompt the user to enter a port number 
		getInfo "Please enter a port number. Make sure this port is not being used by another application."
		WGS_PORT=$infoResult

		# Check if input is a valid number between 1 and 65535
		if ! [[ "$WGS_PORT" =~ ^[0-9]+$ ]] || [ "$WGS_PORT" -lt 1 ] || [ "$WGS_PORT" -gt 65535 ]; then
			echo "${RED}Warning: Invalid port number. Please enter a number between 1 and 65535.${NC}"
			continue
		fi

		# Check if the port is already in use
		if ss -tuln | grep -q ":$WGS_PORT "; then
			echo "${RED}Warning: Port $WGS_PORT is already in use. Please choose another port.${NC}"
		else
			echo "${GREEN}Port $WGS_PORT is free.${NC}"
			break
		fi
	done

	# get number line before last or last
	drop_line=$(sudo iptables -L INPUT --line-numbers | grep "DROP" | awk '{print $1}' | head -n1)
	if [ -z "$drop_line" ]; then
		echo -e "${RED}Warning: DROP rule not found in INPUT chain! Inserting rule at the end.${NC}" >&2 # it is warning
  	drop_line=$(( $(sudo iptables -L INPUT --line-numbers | tail -n1 | awk '{print $1}') + 1 ))
	fi

	sudo iptables -I INPUT $drop_line -p udp --dport $WGS_PORT -j ACCEPT # open port in firewall
	sudo netfilter-persistent save # save iptables

	# assign a wg ip address 
	while true; do
		# Prompt the user to enter an IP address
		getInfo "Type an ip address wireguard network"
		WG_ADDR=$infoResult

		# Strict IPv4 address validation (each octet must be 0–255)
		if [[ "$WG_ADDR" =~ ^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$ ]]; then
			echo "${GREEN}Valid IP address: $WG_ADDR${NC}"
			break
		else
			echo "${RED}Warning: Invalid IP address format. Please try again.${NC}"
		fi
	done

	# write server configuration in the <wg-server>conf
	server_intrface="[Interface]\nPrivateKey = ${WGS_KEY}\nAddress = ${WG_ADDR%.*}.1/24\nListenPort = ${WGS_PORT}\nPostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${INTERFACE} -j MASQUERADE\nPostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE\n"
	write "${server_intrface}" "/etc/wireguard/$CONFIG_FILE.conf"

	# ip forwarding
	echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
	sudo sysctl -p

	# start systemd demon of wireguard
	sudo systemctl enable wg-quick@$CONFIG_FILE.service
	sudo systemctl start wg-quick@$CONFIG_FILE.service
	#sudo systemctl status wg-quick@$CONFIG_FILE.service

	flag="peer"
fi

# ...................PEER...................

if [ $flag = "peer" ]; then

WG_ADDR=$(sudo awk 'BEGIN{FS=" = "} /Address/{print $2}' /etc/wireguard/$CONFIG_FILE.conf)
WGS_PUB=$(sudo cat /etc/wireguard/$CONFIG_FILE-publickey)
WGS_PORT=$(sudo awk 'BEGIN{FS=" = "} /ListenPort/{print $2}' /etc/wireguard/$CONFIG_FILE.conf)

	while [ $loop -gt 0 ] 
	do
		i=$(sudo awk 'BEGIN{peer=0} /Peer/{peer++} END{print peer}' /etc/wireguard/$CONFIG_FILE.conf)
		getInfo "Type peer's name"
		addPeer $infoResult $(( i + 2 )) $WG_ADDR $WGS_PUB $SERVER_IP $WGS_PORT $CONFIG_FILE

		menu "yes no" "Do you want to add another peer?\n"
		if [ $menuResult = "no" ]; then
			loop=0
		fi
	done
fi

sudo systemctl restart wg-quick@$CONFIG_FILE.service
sudo wg show

sudo -u $MY_USER mkdir /home/$MY_USER/upload
sudo cp -r /etc/wireguard/clients_conf /home/$MY_USER/upload

echo -e "${GREEN}\nДля скачивания файлов конфигурации используйте команду:\n\tscp -rO tsebom@${SERVER_IP}:~/upload/ ~/<DIRECTORY>/${NC}"


read -p "Restart server now? [y/N]: " confirm
[[ "$confirm" =~ ^[yY]$ ]] && sudo reboot

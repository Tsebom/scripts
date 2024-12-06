#!/bin/bash
# Установка и настройка wireguard на удаленом сервере

sudo apt update
sudo apt upgrade

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

	if [["$REPLY" =~ ^[1-${#arr[@]}]$]]; then
		menuResult="${arr[$(($REPLY - 1))]}"
	else
		echo "Your selection is not correct"
	fi
}

# write to file ($1= string, $2= path file)
function write {
		local string=$1
		local path=$2

		echo "$string" >> "$path"
}

# get some infirmation from user ($1= message)
function getInfo {
	read -p "${$1} > "
	infoResult="$REPLY"
}

#----------ACTIONS----------

# install wireguard
sudo apt install -y wireguard
# generate server key
sudo wg genkey | sudo tee /etc/wireguard/privatekey | sudo wg pubkey | sudo tee /etc/wireguard/publickey
# permit to privatekey
sudo chmod 600 /etc/wireguard/privatekey
WGS_KEY=$(< /etc/wireguard/privatekey)
WGS_PUB=$(< /etc/wireguard/publickey)

# get a list of interface and display a selection menu
menu "$(getInterface)" "Plase choose the interface:\n\n"
# assign the result of the interface selection to the variable INTERFACE
INTERFACE=$menuResult

# assign wireguard port
getInfo "Type a port number. Be sure this port is not used an another app"
WGS_PORT=$infoResult

# assign wg ip address 
getInfo "Type an ip address wireguard network"
WG_ADDR=$infoResult

# create config file wg-server.conf
sudo touch /etc/wireguard/wg-server.conf

WGS_INTERFACE="[Interface]
PrivateKey = ${WGS_KEY}
Address = ${WG_ADDR%.*}.1/24
ListenPort = ${WGS_PORT}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE"

write "${WGS_INTERFACE}" "/etc/wireguard/wg-server.conf"
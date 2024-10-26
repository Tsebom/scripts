#!/bin/bash
# Установка и настройка wireguard на удаленом сервере

sudo apt update
sudo apt upgrade

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

	for interface in ${arr[@]}
	do
		message+="$i. $interface\n"
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

# install wireguard
sudo apt install -y wireguard
# generate server key
sudo wg genkey | tee /etc/wireguard/privatekey | wg pubkey | tee /etc/wireguard/publickey
# permit to privatekey
sudo chmod 600 /etc/wireguard/privatekey
 
# get a list of interface and display a selection menu
menu "$(getInterface)" "Plase choose the interface:\n\n"
# assign the result of the interface selection to the variable INTERFACE
INTERFACE=$menuResult 


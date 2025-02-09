#!/bin/bash
# Первоначальная настройка сервера
# Перед применением убедиться что есть в наличии ключи ssh
# В папку со скриптом необходимо положить файл публичного ключа ssh "id_rsa.pub"

#-------------VARIABLES-----------------------

MY_USER="tsebom"

#-------------ACTIONS-----------------------

# Добавляем юзера и включаем его в группу sudo
adduser $MY_USER
sudo adduser $MY_USER sudo $MY_USER
touch /etc/sudoers.d/$MY_USER-config
echo -e "$MY_USER ALL=(ALL) ALL" | sudo tee -a /etc/sudoers.d/$MY_USER-config

# Создаем свой конфигурационный фаил ssh
touch /etc/ssh/sshd_config.d/01-$MY_USER-init.conf
echo -e "PermitRootLogin no\nPasswordAuthentication no\nAllowUsers $MY_USER" | sudo tee -a /etc/ssh/sshd_config.d/01-$MY_USER-init.conf

# Перемещаем фаил с публичным ключом 
sudo -u $MY_USER mkdir /home/$MY_USER/.ssh
sudo cp -r id_rsa.pub /home/$MY_USER/.ssh/authorized_keys

sudo apt update -y && sudo apt upgrade -y

# Устанавливаем пакет
sudo apt install tree -y
sudo apt install net-tools -y # install ifconfig
sudo apt install wireguard -y # install wireguard
sudo apt-get install iptables-persistent -y # Устанавливаем iptables-persistent для сохранения настроек iptables

# Настраиваем firewall
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
sudo iptables -A INPUT -j DROP

sudo netfilter-persistent save # Сохранение настроек iptables

# Перезапускаем  ssh
service ssh restart
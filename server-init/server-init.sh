#!/bin/bash
# Первоначальная настройка сервера
# Перед применением убедиться что есть в наличии ключи ssh
# В папку со скриптом необходимо положить файл публичного ключа ssh "id_rsa.pub" 

set -e  # Прерывать выполнение при ошибках

#-------------VARIABLES-----------------------

RED='\033[0;31m' # ANSI red
GREEN='\033[0;32m' # ANSI green
NC='\033[0m' # no color

#-------------CHECKING------------------------

if [[ $EUID -ne 0 ]]; then
    echo "${RED}Warning: Скрипт должен быть запущен от имени root!${NC}"
    exit 1
fi

if [[ ! -f ./id_rsa.pub ]] || [[ ! -f monitor/login_telegram_notify.sh ]] || [[ ! -f monitor/auto_update.sh ]]; then
    echo "${RED}Warning: Файл id_rsa.pub или login_telegram_notify.sh или auto_update.sh не найден!${NC}"
    exit 1
fi

#-------------ADDUSER-------------------------

while true; do
	read -p "Please choose a username: " MY_USER
	# Проверка: поле не пустое
	if [[ -z "$MY_USER" ]]; then
		echo -e "${RED}Warning: Имя пользователя не может быть пустым.${NC}"
		continue
	fi
	
	# Проверка: соответствует шаблону
	if [[ ! "$MY_USER" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_-]{1,31}$ ]]; then
		echo -e "${RED}Warning: Неверный формат имени.${NC}"
		echo -e "${RED}Допустимы только буквы, цифры, '-', '_'. Имя не должно начинаться с '-'. Длина: 2–32 символа.${NC}"
		continue
	fi

	# Проверка: пользователь уже существует
	if id "$MY_USER" &>/dev/null; then
		echo -e "${RED}Warning: Пользователь '$MY_USER' уже существует.${NC}"
		continue
	fi
	break
done

# Добавляем юзера и включаем его в группу sudo
adduser $MY_USER
usermod -aG sudo $MY_USER

touch /etc/sudoers.d/$MY_USER-config
chmod 0440 /etc/sudoers.d/$MY_USER-config
chown root:root /etc/sudoers.d/$MY_USER-config
echo -e "$MY_USER ALL=(ALL) ALL" | tee -a /etc/sudoers.d/$MY_USER-config

#---------------SSH---------------------------

# Перемещаем фаил с публичным ключом 
if [[ ! -d /home/$MY_USER/.ssh ]]; then
	mkdir -p /home/$MY_USER/.ssh
	chmod 700 /home/$MY_USER/.ssh
	chown $MY_USER:$MY_USER /home/$MY_USER/.ssh
fi

cp id_rsa.pub /home/$MY_USER/.ssh/authorized_keys
chmod 600 /home/$MY_USER/.ssh/authorized_keys
chown $MY_USER:$MY_USER /home/$MY_USER/.ssh/authorized_keys

# Создаем свой конфигурационный фаил ssh
touch /etc/ssh/sshd_config.d/01-$MY_USER-init.conf
chmod 644 /etc/ssh/sshd_config.d/01-$MY_USER-init.conf
chown root:root /etc/ssh/sshd_config.d/01-$MY_USER-init.conf

cat <<EOF > /etc/ssh/sshd_config.d/01-$MY_USER-init.conf
PermitRootLogin no
PasswordAuthentication no
AllowUsers $MY_USER
EOF

#------------SYSUPDATE------------------------

apt update -y && apt upgrade -y

# Устанавливаем пакет
apt install curl -y
apt install tree -y
apt install unzip -y
apt install wireguard -y # wireguard
apt install qrencode -y # QR-code
apt-get install iptables-persistent -y # Устанавливаем iptables-persistent для сохранения настроек iptables

#------------FIREWALL-------------------------

# Настраиваем firewall
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
iptables -A INPUT -j DROP
netfilter-persistent save # Сохранение настроек iptables

#-----------TELEGRAM_BOTS---------------------

touch /etc/monitor.conf
chmod 600 /etc/monitor.conf
chown root:root /etc/monitor.conf

read -p "Type the TOKEN for your telegram monitor bot" TOKEN
echo "TOKEN=$TOKEN" >> /etc/monitor.conf 2>/dev/null
read -p "Type your chat_id"  CHAT_ID
echo "CHAT_ID=$CHAT_ID" >> /etc/monitor.conf 2>/dev/null

# add auto_update.sh
cp monitor/auto_update.sh /usr/local/bin/auto_update.sh
chmod 755 /usr/local/bin/auto_update.sh
chown root:root /usr/local/bin/auto_update.sh
(crontab -l 2>/dev/null; echo "0 5 * * 3,6 /usr/local/bin/auto_update.sh") | crontab -

# add login_telegram_notify.sh
cp monitor/login_telegram_notify.sh /usr/local/bin/login_telegram_notify.sh
chmod 755 /usr/local/bin/login_telegram_notify.sh
chown root:root /usr/local/bin/login_telegram_notify.sh
echo "session optional pam_exec.so type=open_session /usr/local/bin/login_telegram_notify.sh" >> /etc/pam.d/sshd

# Перезапускаем  ssh
systemctl restart ssh

#---------------REBOOT------------------------

echo -e "${GREEN}Настройка завершена.${NC}"
echo -e "${GREEN}Сервер будет перезагружен...${NC}"
sleep 3
read -p "Перезагрузить сервер сейчас? [y/N]: " confirm
[[ $confirm =~ ^[yY]$ ]] && reboot

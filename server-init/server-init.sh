#!/bin/bash
# Первоначальная настройка сервера
# Перед применением убедиться что есть в наличии ключи ssh
# В папку со скриптом необходимо положить файл публичного ключа ssh "id_rsa.pub"
# scp -r /path/to/local/folder user@server:/path/to/remote/


set -e  # Прерывать выполнение при ошибках

#-------------VARIABLES-----------------------

RED='\033[0;31m' # ANSI red
GREEN='\033[0;32m' # ANSI green
NC='\033[0m' # no color

TIMEZONE="Europe/Saratov"

#-------------CHECKING------------------------

if [[ $EUID -ne 0 ]]; then
    echo "${RED}Warning: Скрипт должен быть запущен от имени root!${NC}"
    exit 1
fi

if [[ ! -f ./id_rsa.pub ]] || [[ ! -f monitor/login_telegram_notify.sh ]] || [[ ! -f monitor/auto_update.sh ]]; then
    echo "${RED}Warning: Файл id_rsa.pub или login_telegram_notify.debian.sh или auto_update.sh не найден!${NC}"
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
apt install ufw -y
apt install curl -y
apt install tree -y
apt install unzip -y
apt install rsync -y
apt install wireguard -y # wireguard
apt install qrencode -y # QR-code

#------------TIMEZONE-------------------------

timedatectl set-timezone "$TIMEZONE"

#------------DOCKER---------------------------

# Установка зависимостей
apt install apt-transport-https ca-certificates gnupg lsb-release -y

# Добавление GPG ключа Docker
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Добавление официального репозитория Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Установка Docker
apt update -y
apt install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y

# Добавляем пользователя в группу docker
usermod -aG docker $MY_USER
systemctl enable docker
systemctl start docker

#------------FIREWALL-------------------------

ufw allow ssh # Доступ для ssh
ufw enable # firewall on

#-----------TELEGRAM_BOTS---------------------

touch /etc/monitor.conf
chmod 600 /etc/monitor.conf
chown root:root /etc/monitor.conf

read -p "Type the TOKEN for your telegram monitor bot: " TOKEN
echo "TOKEN=$TOKEN" >> /etc/monitor.conf 2>/dev/null
read -p "Type your chat_id: "  CHAT_ID
echo "CHAT_ID=$CHAT_ID" >> /etc/monitor.conf 2>/dev/null

# add auto_update.sh
cp monitor/auto_update.sh /usr/local/bin/auto_update.sh
chmod 755 /usr/local/bin/auto_update.sh
chown root:root /usr/local/bin/auto_update.sh
sudo crontab -l 2>/dev/null | { cat; echo "0 5 * * 3,6 /usr/local/bin/auto_update.sh"; } | sudo crontab -

# add login_telegram_notify.sh (PAM-версия для Debian)
cp monitor/login_telegram_notify.sh /usr/local/bin/login_telegram_notify.sh
chmod 755 /usr/local/bin/login_telegram_notify.sh
chown root:root /usr/local/bin/login_telegram_notify.sh
echo "session optional pam_exec.so type=open_session /usr/local/bin/login_telegram_notify.sh" >> /etc/pam.d/sshd

# Перезапускаем  ssh
systemctl restart ssh

#---------------REBOOT------------------------

echo -e "${GREEN}Настройка завершена.${NC}"
echo -e "${GREEN}Сервер необходимо перезагрузить...${NC}"
sleep 3
read -p "Перезагрузить сервер сейчас? [y/N]: " confirm
[[ $confirm =~ ^[yY]$ ]] && reboot

#!/bin/sh
# OpenWrt 24.10.5 (BusyBox sh, Dropbear или OpenSSH).
# Location: /usr/local/bin/login_telegram_notify.sh
# chmod +x /usr/local/bin/login_telegram_notify.sh
#
# Зависимость: curl (opkg update && opkg install curl)
# Конфиг: /etc/monitor.conf — TOKEN= и CHAT_ID=
#
# Подключение: в конец /etc/profile добавить строку:
#   [ -n "$SSH_CLIENT" ] && /usr/local/bin/login_telegram_notify.sh &
# (& чтобы не задерживать приглашение оболочки; уведомление уходит в фоне)
#
# Примечание: на OpenWrt нет pam_exec для sshd по умолчанию; уведомление
# при интерактивном входе по SSH через переменную SSH_CLIENT.

[ -z "$SSH_CLIENT" ] && exit 0

. /etc/monitor.conf

USER_NAME="${USER:-$(id -un)}"
REMOTE_HOST=$(echo "$SSH_CLIENT" | cut -d' ' -f1)
LOGIN_TIME=$(date +'%T %a %d %b %Y')
ROUTER_NAME=$(uname -n)

MESSAGE=$(printf "🔐 User %s logged in to %s.\n📅 Time:\n%s\n🌐 From:\n%s" \
	"$USER_NAME" "$ROUTER_NAME" "$LOGIN_TIME" "$REMOTE_HOST")

curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
	-d chat_id="${CHAT_ID}" \
	-d text="${MESSAGE}" >/dev/null

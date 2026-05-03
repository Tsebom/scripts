#!/bin/sh /etc/rc.common
# OpenWrt 24.10.5 — уведомление в Telegram после загрузки.
# Location: /etc/init.d/start_notify
# chmod +x /etc/init.d/start_notify
# /etc/init.d/start_notify enable && /etc/init.d/start_notify start
#
# Зависимости: opkg install curl
# Конфиг: /etc/monitor.conf (TOKEN=, CHAT_ID=)

START=99

. /etc/monitor.conf

start() {
	# ждём доступность сети (до ~40 с)
	i=1
	while [ "$i" -le 20 ]; do
		ping -c1 -W3 8.8.8.8 >/dev/null 2>&1 && break
		sleep 2
		i=$((i + 1))
	done

	DATE=$(date +'%T %a %d %b %Y')
	MESSAGE=$(printf "🚀 Router is rebooted!\n%s" "$DATE")

	curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
		-d chat_id="${CHAT_ID}" \
		-d text="${MESSAGE}" >/dev/null
}

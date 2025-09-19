#!/bin/sh /etc/rc.common
#Location: /etc/init.d/start_notify.sh
#Включаем в автозагрузку командой (-- /etc/init.d/start_notify enable --)

START=99

source /etc/monitor.conf

DATE=$(date +'%T %a %d %b %Y')
MESSAGE=$(printf "🚀 Router is rebooted!\n%s" "$DATE")

start() {
    curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="${MESSAGE}" >/dev/null
}

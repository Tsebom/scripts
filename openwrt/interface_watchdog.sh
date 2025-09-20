#!/bin/sh

# Location:
# 	/usr/local/bin/interface_watchdog.sh
# Запуск скрипта для тестирования:
# 	/usr/local/bin/interface_watchdog.sh &
# Для автозапуска добавьте в /etc/rc.local перед exit 0:
# 	/usr/local/bin/interface_watchdog.sh &
# Проверяйте логи в реальном времени:
# 	logread -f | grep watchdog
# Настройте ротацию, чтобы избежать переполнения: 
# 	uci set system.@system[0].log_size=128
# 	uci commit system
# Убить процесс:
# 	ps | grep interface_w*   # Находим процесс
# 	kill <PID>               № PID первая цифра в выдаче

# Настройки
PING_TARGETS="8.8.8.8 1.1.1.1 77.88.8.8 77.88.8.1"  # Цели для проверки интернета
MAX_FAILS=3                                         # Количество неудачных попыток перед рестартом
FAIL_COUNT_WAN=0                                    # Счётчик неудач для WAN
FAIL_COUNT_WIFI0=0                                  # Счётчик неудач для radio0 (wlan0)
FAIL_COUNT_WIFI1=0                                  # Счётчик неудач для radio1 (wlan1)
CHECK_INTERVAL=120                                  # Интервал проверки (секунды)
WAN_INTERFACE="wan"                                 # WAN-интерфейс из uci show network.wan
WIFI_INTERFACES="phy0-ap0 phy1-ap0"                 # WiFi-интерфейсы (radio0 → wlan0, radio1 → wlan1)
RESTART_LOG="/tmp/watchdog_restarts"                # Файл для отслеживания перезапусков
MAX_RESTARTS=5                                      # Максимум перезапусков в сутки
CONFIG_FILE="/etc/monitor.conf"                     # Файл с настройками Telegram

# Загрузка конфигурации Telegram
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    logger -t watchdog "$(date '+%Y-%m-%d %H:%M:%S'): Config file $CONFIG_FILE not found"
    exit 1
fi

# Функция логирования с временной меткой
log() {
    logger -t watchdog "$(date '+%Y-%m-%d %H:%M:%S'): $1"
}

# Функция отправки уведомления через Telegram
notify() {
    local message="$1"
    if [ -n "$TOKEN" ] && [ -n "$CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
             -d chat_id="$CHAT_ID" \
             -d text="$message" >/dev/null 2>&1 || log "Failed to send Telegram notification"
    else
        log "Telegram TOKEN or CHAT_ID not set"
    fi
}

# Функция перезапуска WAN
restart_wan() {
    local restarts=$(cat "$RESTART_LOG" 2>/dev/null || echo 0)
    if [ "$restarts" -ge "$MAX_RESTARTS" ]; then
        log "Max restarts ($MAX_RESTARTS) reached for WAN, rebooting router..."
        #notify "Max restarts ($MAX_RESTARTS) reached for WAN, rebooting router"
        #echo 0 > "$RESTART_LOG"
        reboot
    fi
    log "Restarting WAN interface ($WAN_INTERFACE)"
    ifdown "$WAN_INTERFACE" || log "Failed to bring down WAN"
    sleep 15  # Увеличено для DHCP
    ifup "$WAN_INTERFACE" || log "Failed to bring up WAN"
    sleep 10  # Для появления интернета
    notify "Restarting WAN interface ($WAN_INTERFACE)"
    echo $((restarts + 1)) > "$RESTART_LOG"
}

# Функция перезапуска WiFi
restart_wifi() {
    local radio="$1"
    local restarts=$(cat "$RESTART_LOG" 2>/dev/null || echo 0)
    if [ "$restarts" -ge "$MAX_RESTARTS" ]; then
        log "Max restarts ($MAX_RESTARTS) reached for WiFi ($radio), rebooting router..."
        notify "Max restarts ($MAX_RESTARTS) reached for WiFi ($radio), rebooting router"
        #echo 0 > "$RESTART_LOG"
        reboot
    fi
    log "Restarting WiFi ($radio)"
    notify "Restarting WiFi ($radio)"
    wifi reload "$radio" || log "Failed to reload WiFi ($radio)"
    echo $((restarts + 1)) > "$RESTART_LOG"
}

# Функция проверки состояния интерфейса
check_interface_status() {
    local interface="$1"
    if ! ip link show "$interface" | grep -q "UP"; then
        log "Interface $interface is DOWN"
        return 1
    fi
    return 0
}

# Функция проверки IP-адреса (для WAN)
check_ip_address() {
    local interface="$1"
    if ! ip addr show "$interface" | grep -q "inet "; then
        log "Interface $interface has no IP address (DHCP failure)"
        return 1
    fi
    return 0
}

# Функция проверки интернета через пинг
check_internet() {
    for target in $PING_TARGETS; do
        if ping -c 2 -W 2 "$target" >/dev/null 2>&1; then
            return 0  # Успешный пинг
        fi
    done
    log "No internet access"
    return 1
}

# Функция проверки WiFi через wifi status
check_wifi_status() {
    local radio="$1"
    if ! wifi status | grep -A5 "\"$radio\"" | grep -q '"up": true'; then
        log "WiFi $radio is not up"
        notify "WiFi $radio is not up"
        return 1
    fi
    return 0
}

# Очистка счётчика перезапусков (ежедневно)
check_restart_count() {
    local last_reset=$(stat -c %Y "$RESTART_LOG" 2>/dev/null || echo 0)
    local current_time=$(date +%s)
    local one_day=$((24 * 3600))
    if [ $((current_time - last_reset)) -gt "$one_day" ]; then
        echo 0 > "$RESTART_LOG"
        log "Restart counter reset for new day"
    fi
}

# Основной цикл
while true; do
    # Проверка счётчика перезапусков
    check_restart_count

    # Проверка WAN
    wan_status="ok"
    if ! check_interface_status "$WAN_INTERFACE"; then
        wan_status="down"
    elif ! check_ip_address "$WAN_INTERFACE"; then
        wan_status="no_ip"
    elif ! check_internet; then
        wan_status="no_internet"
    else
        FAIL_COUNT_WAN=0
        log "WAN check passed"
    fi

    # Обработка проблем с WAN
    if [ "$wan_status" != "ok" ]; then
        FAIL_COUNT_WAN=$((FAIL_COUNT_WAN + 1))
        log "WAN failure ($FAIL_COUNT_WAN/$MAX_FAILS): $wan_status"
        if [ "$FAIL_COUNT_WAN" -ge "$MAX_FAILS" ]; then
            restart_wan
            FAIL_COUNT_WAN=0
        fi
    fi

    # Проверка WiFi (radio0/wlan0 и radio1/wlan1)
    for wifi_iface in $WIFI_INTERFACES; do
        wifi_status="ok"

        # Из имени "phy*-ap0" вытащим номер радиомодуля (1)
        phy="${wifi_iface%%-*}"           # даст "phy0" или "phy1"
        phy_num="${phy#phy}"              # удалит "phy" → останется 0 или 1
        radio="radio${phy_num}"           # соберём radio0, radio1

        if ! check_interface_status "$wifi_iface"; then
            wifi_status="down"
        elif ! check_wifi_status "$radio"; then
            wifi_status="not_up"
        else
            if [ "$wifi_iface" = "${WIFI_INTERFACES%% *}" ]; then
                FAIL_COUNT_WIFI0=0
            else
                FAIL_COUNT_WIFI1=0
            fi
            log "WiFi $wifi_iface (radio: $radio) check passed"
        fi

        # Обработка проблем с WiFi
        if [ "$wifi_status" != "ok" ]; then
            if [ "$wifi_iface" = "${WIFI_INTERFACES%% *}" ]; then
                FAIL_COUNT_WIFI0=$((FAIL_COUNT_WIFI0 + 1))
                log "WiFi $wifi_iface failure ($FAIL_COUNT_WIFI0/$MAX_FAILS): $wifi_status"
                if [ "$FAIL_COUNT_WIFI0" -ge "$MAX_FAILS" ]; then
                    restart_wifi "radio0"
                    FAIL_COUNT_WIFI0=0
                fi
            else
                FAIL_COUNT_WIFI1=$((FAIL_COUNT_WIFI1 + 1))
                log "WiFi $wifi_iface failure ($FAIL_COUNT_WIFI1/$MAX_FAILS): $wifi_status"
                if [ "$FAIL_COUNT_WIFI1" -ge "$MAX_FAILS" ]; then
                    restart_wifi "radio1"
                    FAIL_COUNT_WIFI1=0
                fi
            fi
        fi
    done

    # Задержка перед следующей проверкой
    sleep "$CHECK_INTERVAL"
done
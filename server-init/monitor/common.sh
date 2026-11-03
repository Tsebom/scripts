#!/bin/bash
# Общие функции для системы мониторинга
# Location: /etc/monitor/common.sh

# Загрузка конфигурации
CONF_FILE="/etc/monitor.conf"
if [[ -f "$CONF_FILE" ]]; then
    source "$CONF_FILE"
else
    # Если конфиг не найден, пытаемся выйти с ошибкой, если мы не в режиме установки
    if [[ "$1" != "--install" ]]; then
        echo "Error: Configuration file $CONF_FILE not found." >&2
        exit 1
    fi
fi

# Функция отправки сообщений в Telegram
send_telegram() {
    local message="$1"
    local parse_mode="${2:-Markdown}"

    if [[ -z "$TOKEN" || -z "$CHAT_ID" ]]; then
        echo "Error: TOKEN or CHAT_ID is not defined." >&2
        return 1
    fi

    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$message" \
        -d parse_mode="$parse_mode" \
        > /dev/null
}

# Форматирование даты
get_timestamp() {
    date +'%T %a %d %b %Y'
}

# Получение имени хоста (с фолбеком)
get_hostname() {
    if [[ -n "$HOSTNAME" ]]; then
        echo "$HOSTNAME"
    else
        hostname -f 2>/dev/null || hostname
    fi
}

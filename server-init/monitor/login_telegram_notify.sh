#!/bin/bash
# Уведомление о входе в систему
# Location: /usr/local/bin/login_telegram_notify.sh
# PAM: session optional pam_exec.so type=open_session /usr/local/bin/login_telegram_notify.sh

set -u

# Загрузка общего модуля
COMMON_MOD="/etc/monitor/common.sh"
if [[ -f "$COMMON_MOD" ]]; then
    source "$COMMON_MOD"
else
    exit 1
fi

# Переменные PAM
USER_NAME="${PAM_USER:-unknown}"
REMOTE_HOST="${PAM_RHOST:-unknown}"
SVR_NAME=$(get_hostname)
TIMESTAMP=$(get_timestamp)

# Формирование сообщения
MESSAGE=$(printf "🔐 *User %s* logged in to server *%s*\n\n📅 Time: %s\n🌐 Host: %s" \
    "$USER_NAME" "$SVR_NAME" "$TIMESTAMP" "$REMOTE_HOST")

# Отправка
send_telegram "$MESSAGE"

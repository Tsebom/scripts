#!/bin/bash
# Автоматическое обновление системы
# Location: /usr/local/bin/auto_update.sh
# Crontab: 0 5 * * 3,6 /usr/local/bin/auto_update.sh

set -u # Ошибка при использовании неопределенных переменных

# Загрузка общего модуля
COMMON_MOD="/etc/monitor/common.sh"
if [[ -f "$COMMON_MOD" ]]; then
    source "$COMMON_MOD"
else
    echo "Error: Common module $COMMON_MOD not found." >&2
    exit 1
fi

LOG_FILE="/var/log/update-output.log"
ERR_FILE="/var/log/update-errors.log"
SVR_NAME=$(get_hostname)
TIMESTAMP=$(get_timestamp)

# Создание лог-файлов с правильными правами
for FILE in "$LOG_FILE" "$ERR_FILE"; do
    if [[ ! -f "$FILE" ]]; then
        touch "$FILE"
        chmod 640 "$FILE"
    fi
done

# Выполнение обновления
{
    echo "========== [$TIMESTAMP] Starting system update =========="
    apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get autoremove -y && \
    apt-get autoclean
    echo "========== Update finished =========="
    echo ""
} > "$LOG_FILE" 2>"$ERR_FILE"

# Проверка статуса завершения последней команды в блоке
if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
    # Парсинг результата обновления
    # Ищем строку с количеством обновленных пакетов
    result_update=$(grep -E '[0-9]+ upgraded, [0-9]+ newly installed' "$LOG_FILE" | tail -n 1 | sed 's/^[ \t]*//;s/\.$//')
    
    if [[ -z "$result_update" ]]; then
        result_update="Система уже обновлена."
    else
        # Превращаем строку в список с буллитами
        result_update=$(echo "$result_update" | sed 's/, / \n• /g' | sed 's/^/• /')
    fi
    
    TEXT=$(printf "✅ *%s* server update succeeded:\n📅 %s\n\n%s" "$SVR_NAME" "$TIMESTAMP" "$result_update")
else
    # Сбор фрагмента ошибки
    LOG_SNIPPET=$(tail -n 20 "$ERR_FILE")
    TEXT=$(printf "❌ *%s* server update Error:\n📅 %s\n\nLog snippet:\n\`\`\`\n%s\n\`\`\`" "$SVR_NAME" "$TIMESTAMP" "$LOG_SNIPPET")
fi

# Отправка уведомления
send_telegram "$TEXT"

# Проверка необходимости перезагрузки
if [[ -f /var/run/reboot-required ]]; then
    send_telegram "⚙️ *%s* restart required, rebooting now..." "$SVR_NAME"
    shutdown -r now
fi

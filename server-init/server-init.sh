#!/bin/bash
# Первоначальная настройка сервера
#
# Пример полного автоматического запуска:
# ./server-init.sh SSH_KEY="ssh-rsa AAA..." TOKEN="123456789:ABCDefGhI..." CHAT_ID="12345678"
#
# Запуск в интерактивном режиме:
# ./server-init.sh

set -e  # Прерывать выполнение при ошибках

#-------------VARIABLES-----------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TIMEZONE="Europe/Saratov"
PACKAGES=(
    "ufw"
    "curl"
    "tree"
    "unzip"
    "rsync"
    "wireguard"
    "qrencode"
)

#-------------LOGGING--------------------------
log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()  { echo -e "${RED}[ERROR]${NC} $1"; }

#-------------HELPERS--------------------------
prompt_input() {
    local prompt_text="$1"
    local regex="$2"
    local error_msg="$3"
    local input=""

    while true; do
        read -p "$prompt_text: " input
        if [[ -z "$input" ]]; then
            log_warn "Поле не может быть пустым."
            continue
        fi
        if [[ -n "$regex" ]] && [[ ! "$input" =~ $regex ]]; then
            log_warn "$error_msg"
            continue
        fi
        echo "$input"
        return 0
    done
}

#-------------FUNCTIONS------------------------

check_requirements() {
    log_info "Проверка требований..."
    if [[ $EUID -ne 0 ]]; then
        log_error "Скрипт должен быть запущен от имени root!"
        exit 1
    fi

    local req_files=("monitor/login_telegram_notify.sh" "monitor/auto_update.sh")
    for file in "${req_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Файл $file не найден!"
            exit 1
        fi
    done
    log_success "Все требования выполнены."
}

setup_hostname() {
    log_info "Настройка Hostname..."
    local hostname_regex="^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$"
    local hostname_err="Неверный формат. Допустимы буквы, цифры и '-'. Длина: 2-63 символа."
    
    local hostname=$(prompt_input "Please choose a hostname" "$hostname_regex" "$hostname_err")
    
    hostnamectl set-hostname "$hostname"
    
    if grep -qE '^127\.0\.1\.1[[:space:]]+' /etc/hosts; then
        sed -i -E "s/^127\.0\.1\.1[[:space:]]+.*/127.0.1.1\t$hostname/" /etc/hosts
    else
        echo -e "127.0.1.1\t$hostname" >> /etc/hosts
    fi
    log_success "Hostname установлен: $hostname"
}

setup_user() {
    log_info "Настройка пользователя..."
    local user_regex="^[a-zA-Z0-9_][a-zA-Z0-9_-]{1,31}$"
    local user_err="Неверный формат. Допустимы буквы, цифры, '-', '_'. Длина: 2–32 символа."
    
    while true; do
        local username=$(prompt_input "Please choose a username" "$user_regex" "$user_err")
        if id "$username" &>/dev/null; then
            log_warn "Пользователь '$username' уже существует."
            continue
        fi
        break
    done

    adduser --gecos "" "$username"
    usermod -aG sudo "$username"

    local sudo_conf="/etc/sudoers.d/$username-config"
    echo "$username ALL=(ALL) ALL" > "$sudo_conf"
    chmod 0440 "$sudo_conf"
    chown root:root "$sudo_conf"

    # Проверка синтаксиса sudoers
    if ! visudo -cf "$sudo_conf" &>/dev/null; then
        log_error "Ошибка в конфигурации sudoers для $username! Удаление файла."
        rm -f "$sudo_conf"
        exit 1
    fi
    
    log_success "Пользователь $username создан и добавлен в sudo."
    # Сохраняем имя пользователя для последующих этапов
    MY_USER="$username"
}

setup_ssh() {
    local arg_ssh_key="$1"
    log_info "Настройка SSH..."
    local ssh_dir="/home/$MY_USER/.ssh"
    
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    chown "$MY_USER:$MY_USER" "$ssh_dir"

    # Ввод ключа: из аргумента или через ввод
    local ssh_key=""
    if [[ -n "$arg_ssh_key" ]]; then
        ssh_key="$arg_ssh_key"
        log_info "Используем переданный SSH-ключ."
    else
        while true; do
            read -s -p "Paste your public SSH key: " ssh_key
            echo
            if [[ -z "$ssh_key" ]]; then
                log_warn "Публичный SSH-ключ не может быть пустым."
                continue
            fi
            break
        done
    fi

    echo "$ssh_key" > "$ssh_dir/authorized_keys"
    chmod 600 "$ssh_dir/authorized_keys"
    chown "$MY_USER:$MY_USER" "$ssh_dir/authorized_keys"

    local ssh_conf="/etc/ssh/sshd_config.d/01-$MY_USER-init.conf"
    cat <<EOF > "$ssh_conf"
PermitRootLogin no
PasswordAuthentication no
AllowUsers $MY_USER
EOF
    chmod 644 "$ssh_conf"
    chown root:root "$ssh_conf"

    log_success "SSH настроен (root login disabled, password auth disabled)."
}

setup_packages() {
    log_info "Обновление системы и установка пакетов..."
    apt update -y && apt upgrade -y
    
    # Установка из массива
    apt install -y "${PACKAGES[@]}"
    log_success "Базовые пакеты установлены."
}

setup_timezone() {
    log_info "Настройка часового пояса..."
    timedatectl set-timezone "$TIMEZONE"
    log_success "Часовой пояс установлен на $TIMEZONE."
}

setup_docker() {
    log_info "Установка Docker..."
    apt install -y apt-transport-https ca-certificates gnupg lsb-release

    # GPG Key
    local gpg_path="/usr/share/keyrings/docker-archive-keyring.gpg"
    curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg" | gpg --dearmor -o "$gpg_path" --yes

    # Repo
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$gpg_path] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    usermod -aG docker "$MY_USER"
    systemctl enable docker
    systemctl start docker
    log_success "Docker установлен и настроен."
}

setup_firewall() {
    log_info "Настройка Firewall..."
    ufw allow ssh
    ufw --force enable
    log_success "UFW включен, SSH разрешен."
}

setup_monitoring() {
    local arg_token="$1"
    local arg_chat_id="$2"

    log_info "Настройка Telegram-мониторинга..."
    local conf_file="/etc/monitor.conf"
    local monitor_dir="/etc/monitor"
    
    # Определяем token: из аргумента или через ввод
    local token=""
    if [[ -n "$arg_token" ]]; then
        token="$arg_token"
        log_info "Используем переданный TOKEN."
    else
        token=$(prompt_input "Type the TOKEN for your telegram monitor bot" "" "")
    fi

    # Определяем chat_id: из аргумента или через ввод
    local chat_id=""
    if [[ -n "$arg_chat_id" ]]; then
        chat_id="$arg_chat_id"
        log_info "Используем переданный CHAT_ID."
    else
        chat_id=$(prompt_input "Type your chat_id" "" "")
    fi

    cat <<EOF > "$conf_file"
TOKEN=$token
CHAT_ID=$chat_id
EOF
    chmod 600 "$conf_file"
    chown root:root "$conf_file"

    # Создаем директорию для общего модуля
    mkdir -p "$monitor_dir"
    chmod 755 "$monitor_dir"

    # Установка общего модуля
    local common_bin="$monitor_dir/common.sh"
    cp monitor/common.sh "$common_bin"
    chmod 644 "$common_bin"
    chown root:root "$common_bin"

    # Auto update script
    local auto_update_bin="/usr/local/bin/auto_update.sh"
    cp monitor/auto_update.sh "$auto_update_bin"
    chmod 755 "$auto_update_bin"
    chown root:root "$auto_update_bin"

    systemctl enable cron
    systemctl start cron
    # Идемпотентное добавление в crontab
    (crontab -l 2>/dev/null | grep -vxF "0 5 * * 3,6 $auto_update_bin" || true; echo "0 5 * * 3,6 $auto_update_bin") | crontab -

    # Login notify script
    local login_notify_bin="/usr/local/bin/login_telegram_notify.sh"
    cp monitor/login_telegram_notify.sh "$login_notify_bin"
    chmod 755 "$login_notify_bin"
    chown root:root "$login_notify_bin"

    local pam_line="session optional pam_exec.so type=open_session $login_notify_bin"
    grep -qxF "$pam_line" /etc/pam.d/sshd || echo "$pam_line" >> /etc/pam.d/sshd

    systemctl restart ssh
    log_success "Мониторинг настроен с использованием общего модуля."
}

#-------------MAIN------------------------------

main() {
    # Парсинг аргументов для автоматизации
    local parsed_ssh_key=""
    local parsed_token=""
    local parsed_chat_id=""

    for arg in "$@"; do
        case $arg in
            SSH_KEY=*)
                parsed_ssh_key="${arg#*=}"
                ;;
            TOKEN=*)
                parsed_token="${arg#*=}"
                ;;
            CHAT_ID=*)
                parsed_chat_id="${arg#*=}"
                ;;
        esac
    done

    clear
    echo -e "${BLUE}=========================================="
    echo -e "   Server Initial Setup Script (Refactored)"
    echo -e "==========================================${NC}\n"

    check_requirements
    setup_hostname
    setup_user
    setup_ssh "$parsed_ssh_key"
    setup_packages
    setup_timezone
    setup_docker
    setup_firewall
    setup_monitoring "$parsed_token" "$parsed_chat_id"

    echo -e "\n${GREEN}=========================================="
    echo -e "Настройка завершена успешно!"
    echo -e "Сервер необходимо перезагрузить..."
    echo -e "==========================================${NC}"
    
    sleep 2
    read -p "Перезагрузить сервер сейчас? [y/N]: " confirm
    if [[ $confirm =~ ^[yY]$ ]]; then
        reboot
    fi
}

main "$@"

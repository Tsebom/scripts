# scripts

Набор shell-скриптов для развёртывания и администрирования серверов (Debian/Ubuntu, OpenWrt) с уведомлениями в Telegram.

## Структура

| Каталог | Назначение |
|---|---|
| `server-init/` | Инициализация сервера с нуля + Telegram-мониторинг |
| `wireguard/` | Развёртывание WireGuard-сервера и клиентов |
| `openwrt/` | Скрипты для роутера OpenWrt: уведомления в Telegram |
| `user_env/` | Настройка пользовательской среды (fish, exa, node, tmux) |
| `temp/` | Архив старых прототипов |

## server-init

`server-init.sh` — главный скрипт, запускать от root. Выполняет по порядку:

1. настройка hostname
2. создание пользователя с sudo
3. SSH только по ключу (`PermitRootLogin no`, `PasswordAuthentication no`, `AllowUsers`)
4. базовые пакеты (ufw, curl, wireguard, qrencode, ...)
5. часовой пояс `Europe/Saratov`
6. Docker из официального репозитория
7. UFW (открыт только SSH)
8. Telegram-мониторинг

```sh
# интерактивный режим
./server-init.sh

# автоматический режим
./server-init.sh SSH_KEY="ssh-rsa AAA..." TOKEN="123456789:ABCDefGhI..." CHAT_ID="12345678"
```

`monitor/` — модули мониторинга, устанавливаются скриптом:

| Файл | Куда копируется | Роль |
|---|---|---|
| `common.sh` | `/etc/monitor/common.sh` | общие функции (`send_telegram`, `get_timestamp`, `get_hostname`) |
| `auto_update.sh` | `/usr/local/bin/auto_update.sh` | cron `0 5 * * 3,6`: `apt dist-upgrade` + отчёт в Telegram, авто-reboot при необходимости |
| `login_telegram_notify.sh` | `/usr/local/bin/login_telegram_notify.sh` | уведомление о входе по SSH через PAM (`pam_exec`) |

Конфиг: `/etc/monitor.conf` (переменные `TOKEN=`, `CHAT_ID=`).

## wireguard

`wireguard_server.sh` — интерактивный мастер:

- выбор интерфейса, проверка свободного порта, правила iptables, NAT
- генерация ключей сервера, создание `/etc/wireguard/<имя>.conf`
- добавление peers: клиентские конфиги и QR-коды в `/etc/wireguard/clients_conf/`
- копия конфигов в `~/upload` для переноса: `scp -rO <user>@<ip>:~/upload/ ~/<dir>/`

## openwrt

Для роутера OpenWrt (BusyBox sh). Требуют `curl`: `opkg update && opkg install curl`. Конфиг — `/etc/monitor.conf` (`TOKEN=`, `CHAT_ID=`).

- `login_telegram_notify.sh` → `/usr/local/bin/` — уведомление об SSH-входе (в конец `/etc/profile`):
  `[ -n "$SSH_CLIENT" ] && /usr/local/bin/login_telegram_notify.sh &`
- `start_notify.sh` → `/etc/init.d/` — сервис «роутер перезапущен» после загрузки
  (запуск: `/etc/init.d/start_notify enable && /etc/init.d/start_notify start`)
- `list.list` — список разрешаемых доменов

## user_env

`conf_init.sh` — настройка пользовательской среды:

- fish shell как дефолтный (omf, тема soerfish, плагин fzf.fish)
- exa (вместо ls), fzf, tmux
- NVM + Node.js LTS
- алиасы (`af`, `lr`, `ll`, `t`)

Готовые конфиги — в `configs/` (tmux).

## temp

Прототипы, заменённые новыми скриптами (`fish_theme.fish` → `user_env/conf_init.sh`).

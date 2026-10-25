#!/bin/bash
# Location: /usr/local/bin/login_telegram_notify.sh
# Add to PAM: /etc/pam.d/sshd (-- session optional pam_exec.so type=open_session /usr/local/bin/login_telegram_notify.sh --)

source /etc/monitor.conf

# get username and IP
USER_NAME=$PAM_USER
REMOTE_HOST=$PAM_RHOST

LOGIN_TIME=$(date +'%T %a %d %b %Y')

# set the message
MESSAGE=$(printf "🔐 User %s logged in to the server %s.\n📅 Time:\n%s\n🌐 Host:\n%s" "$USER_NAME" "$HOSTNAME" "$LOGIN_TIME" "$REMOTE_HOST")

curl -s -X POST https://api.telegram.org/bot$TOKEN/sendMessage \
	-d chat_id="$CHAT_ID" \
	-d text="$MESSAGE" \
	-d parse_mode="Markdown" \
	> /dev/null

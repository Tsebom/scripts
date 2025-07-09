#!/bin/bash
# upgrade system
# Location: /usr/local/bin/auto_update.sh
# Crontab example: (-- 0 5 * * 3,6 /usr/local/bin/auto_update.sh --)

source /etc/monitor.conf

LOG_FILE="/var/log/update-output.log"
ERR_FILE="/var/log/update-errors.log"

DATE=$(date +'%a %b %d %T %Z %Y')
STATUS=0

telegram() {
	local message="$1"

	curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
	-d chat_id="$CHAT_ID" \
	-d text="$message" \
	-d parse_mode="Markdown" \
	> /dev/null
}

# create file if not exist
for FILE in "$LOG_FILE" "$ERR_FILE"; do
  if [ ! -f "$FILE" ]; then
    touch "$FILE"
    chown :sudo "$FILE"
    chmod 760 "$FILE"
  fi
done

# get upgrade
{
echo "========== [$DATE] Starting system update =========="
apt-get update || STATUS=1
apt-get dist-upgrade -y || STATUS=1
apt-get autoremove -y || STATUS=1
apt-get autoclean || STATUS=1
echo "========== [$DATE] Update finished =========="
echo ""
} > "$LOG_FILE" 2>"$ERR_FILE"

# get result
if [ "$STATUS" -eq 0 ];then
		result_update=$(grep -E '[0-9]+ upgraded, [0-9]+ newly installed, [0-9]+ to remove and [0-9]+ not upgraded' "$LOG_FILE" | \
		head -n 1 | \
		awk -F'(,| and )' '
		function trim(s) {
			gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s)
			gsub(/\.$/, "", s)  # удаляет точку в конце строки, если есть
			return s
		}
		{ for(i=1; i<=NF; i++) print "• " trim($i) }')
	
	TEXT=$(printf "✅ %s server update succeeded:\n%s\nCalculating upgrade:\n%s" "$HOSTNAME" "$DATE" "$result_update")
else
	LOG_SNIPPET=$(tail -n 30 "$ERR_FILE")
	TEXT=$(printf "❌ %s server update Error:\n%s\nLog file:\n```\n%s\n```" \
    "$HOSTNAME" \
    "$DATE" \
    "$LOG_SNIPPET")
fi

telegram "$TEXT"

if [ -f /var/run/reboot-required ]; then
	TEXT=$(printf "⚙️ %s restart required, rebooting now..." "$HOSTNAME")
	telegram "$TEXT"
  shutdown -r now
fi

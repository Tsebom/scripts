#!/bin/bash
# for cheek website available
# Location: /usr/local/bin/site_status.sh
# Crontab example: (-- */5 * * * * /usr/local/bin/site_status.sh --)

source /etc/monitor.conf

DATE=$(date +'%a %b %d %T %Z %Y')
WEBSITE="tsebom.ru"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://$WEBSITE)

if [ "$HTTP_CODE" != "200" ];then	
	TEXT=$(printf "❌ The site %s is not available.\nStatus code: %s\n%s" "$WEBSITE" "$HTTP_CODE" "$DATE")

	curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
		-d chat_id="$CHAT_ID" \
		-d text="$TEXT" \
		-d parse_mode="Markdown" \
		> /dev/null
fi

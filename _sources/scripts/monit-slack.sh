#!/bin/bash

URL=$MONIT_SLACK_HOOK

if [ -z "$URL" ]
  then
    # Do nothing, exit silently
    exit 0
fi

COLOR=${MONIT_COLOR:-$([[ $MONIT_EVENT == *"Exists"* || $MONIT_EVENT == *"succeeded"*  ]] && echo good || echo danger)}
ICON=${MONIT_COLOR:-$([[ $MONIT_EVENT == *"Exists"* || $MONIT_EVENT == *"succeeded"* ]] && echo ✅ || echo ⚠️)}
TEXT=$(echo -e "$ICON $MONIT_EVENT: $MONIT_DESCRIPTION" | python3 -c "import json,sys;print(json.dumps(sys.stdin.read()))")

PAYLOAD="{
  \"attachments\": [
    {
      \"text\": $TEXT,
      \"color\": \"$COLOR\",
      \"mrkdwn_in\": [\"text\"],
      \"fields\": [
        { \"title\": \"Host\", \"value\": \"$MONIT_HOST\", \"short\": true },
        { \"title\": \"Service\", \"value\": \"$MONIT_SERVICE\", \"short\": true },
        { \"title\": \"Date\", \"value\": \"$MONIT_DATE\", \"short\": true }
      ]
    }
  ]
}"

curl -s -X POST --data-urlencode "payload=$PAYLOAD" $URL

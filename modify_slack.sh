# Simple implementation of slack chat.update method
#
# $1 - message new text
# $2 - message timestamp
# $3 - slack api key
# $4 - slack channel id with message
#
# All argumets are REQUIRED
message_text=$1
message_ts=$2
slack_api_key=$3
channel_id=$4
sent_message=$(curl -s -d "channel=$channel_id" \
            -d "text=$message_text" \
            -d "ts=$message_ts" \
            -H "Authorization: Bearer $slack_api_key" \
            -X POST https://slack.com/api/chat.update)
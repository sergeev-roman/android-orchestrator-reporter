# Simple implementation of telegram sendMessage method
#
# $1 - message new text
# $2 - telegram bot token
# $3 - telegram channel id with message
#
# Returns sent message_id
message=$1
bot_token=$2
chat_id=$3

sent_message=$(curl -s -X POST \
    -H 'Content-Type: application/json' \
    -d '{"chat_id": "'"$chat_id"'", "text": "'"$message"'", "disable_notification": true}' \
    https://api.telegram.org/bot$bot_token/sendMessage)

# Gets message id from the response
message_id=$(echo "$sent_message" | grep -o '"message_id":[0-9]*' | sed 's/"message_id"://')
echo "$message_id"
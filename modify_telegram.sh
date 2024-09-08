# Simple implementation of telegram editMessageText method
#
# $1 - message new text
# $2 - message id
# $3 - telegram bot token
# $4 - telegram channel id with message
#
# All argumets are REQUIRED
text=$1
message_id=$2
bot_token=$3
chat_id=$4
    
send_message=$(curl -s -X POST \
    -H 'Content-Type: application/json' \
    -d '{"chat_id": "'"$chat_id"'", "message_id": "'"$message_id"'", "text":"'"$text"'","disable_notification": true}' \
    https://api.telegram.org/bot$bot_token/editMessageText)
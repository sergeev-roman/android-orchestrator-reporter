# Simple implementation of slack chat.postMessage method
#
# $1 - REQUIRED message new text
# $2 - REQUIRED slack api token
# $3 - REQUIRED slack channel id with message
# $4 - OPTIONAL thread_ts; if set, the message will be sent in the thread
#
# Returns sent message timestamp
message=$1
slack_api_key=$2
channel_id=$3
thread_ts=$4

curl_args=(
    -s
    -d "text=$message"
    -d "channel=$channel_id"
    -H "Authorization: Bearer $slack_api_key"
    -X POST "https://slack.com/api/chat.postMessage"
)

# If thread_ts is set, then put in to curl args
if [ -n "$thread_ts" ]; then
    curl_args+=(-d "thread_ts=$thread_ts")
fi

# Execute the curl command and keep response
sent_message=$(curl "${curl_args[@]}")

# Rules for formatting the response
timestamp_regex='"ts":"[^"]*'
only_digits_regex="s/[^0-9.]//g"

# Return message timestamp
echo "${sent_message}" | grep -o "$timestamp_regex" | sed "$only_digits_regex" | head -1
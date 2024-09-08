#!/bin/bash
#
# 
# Sample of implementation to call orchestrator android autotests using monitor-output.sh
# Does not require any additional arguments
#
# Set params below is required
runner="androidx.test.runner.AndroidJUnitRunner"                                    # Default runner; if you use custom - you can change it here
test_package="io.readlui.testapp.test"                                              # Default test package; Change to your 
telegram_bot_token="7152891017:AAGbr4osyX2Cs560sMBDsboz5iXUGHXo6cM"                 # Change to your telegram bot token
telegram_chat_id="-1002391815391"                                                   # Change to your telegram chat id
telegram_status_chat_id="-4581150894"                                               # Change to your telegram statuses chat id; can be same as telegram_chat_id
default_slack_api_key="xoxb-3059311361079-7657686256662-r2cAQpY1ydEhgNtyzOQDrqAt"   # Change to your slack token 
default_slack_channel_id="C07KX3P797T"                                              # Change to your slack channel id

storage="/data/local/tmp"                                                           # Base files push storage in android device; you can keep it default

# Base shell execution comand; recommend to keep it default
shell_base='CLASSPATH=$(pm path androidx.test.services) app_process / \
                            androidx.test.services.shellexecutor.ShellMain am instrument -r -w '
orchestrator="androidx.test.orchestrator/.AndroidTestOrchestrator"

header_file="header.txt"                                                            # Set file for keep header here
header_message="$1"                                                                 # Default run header message
if [ -z "$header_message" ]; then 
    header_message="MY RUN MESSAGE" 
fi    
echo "$header_message">$header_file

# Simple implementation of send message to telegram api
send_telegram() {
    if [[ "$1" == *"$header_message"* ]]; then
        chat_id=$telegram_status_chat_id
    else 
        chat_id=$telegram_chat_id
    fi
    ./send_telegram.sh "$1" "$telegram_bot_token" "$chat_id"
    wait
}

#  Simple implementation of edit message to telegram api
modify_telegram() {
    if [[ "$1" == *"$header_message"* ]]; then
        chat_id=$telegram_status_chat_id
    else 
        chat_id=$telegram_chat_id    
    fi    
    ./modify_telegram.sh "$1" "$2" "$telegram_bot_token" "$chat_id" 
    wait
}

#  Simple implementation of send message to slack api
send_slack() {
    ./send_slack.sh "$1" "$default_slack_api_key" "$default_slack_channel_id"
    wait
}

#  Simple implementation of edit message to slack api
modify_slack() {
    ./modify_slack.sh "$1" "$2" "$default_slack_api_key" "$default_slack_channel_id" 
    wait
}


# Get your header message id
header_message_id=$(send_telegram "$header_message")
wait


# You can set you devices here, also you can put here variable with devices ids 
for device in emulator-5554 emulator-5556; do
{ { 

    # Push main and test apk files to device storage
    adb -s $device push "./main.apk" "$storage"
    adb -s $device push "./test.apk" "$storage"

    # Uninstall services and orchestrator from device, not nessesary but helps to keep it clean 
    adb -s $device uninstall androidx.test.services
    adb -s $device uninstall androidx.test.orchestrator 

    # Push orchestrator and test services apk files to device storage
    adb -s $device push "./orchestrator-1.5.0-alpha01.apk" "$storage/androidx.test.orchestrator"
    adb -s $device push "./test-services-1.5.0-alpha01.apk" "$storage/androidx.test.services"

    # Install services and orchestrator in device
    adb -s $device shell pm install -t -r  --force-queryable "$storage/androidx.test.orchestrator"
    adb -s $device shell pm install -t -r  --force-queryable "$storage/androidx.test.services"

    # Install main and test apks
    adb -s $device shell pm install -t -r "$storage/main.apk"
    adb -s $device shell pm install -t -r "$storage/test.apk"

    # Mock shards, you can use your own logic here
    if [[ "$device" -eq "emulator-5554" ]]; then
        shard=0
    else
        shard=1
    fi

    # Build adb device for run tests on device
    command="adb -s $device shell '${shell_base} \
            -e numShards \"2\" \
            -e shardIndex \"${shard}\" \
            -e targetInstrumentation $test_package/"$runner" \
            ${orchestrator}'"


    header_device_message="$device STATUS: "                    # Build basic header device status message here
    echo "$header_device_message">>$header_file

    # Eval monitor orchestrator output script
    # Uncomment -s -m if you want to use custom send and modify message fun
    source ./monitor-output.sh -c "${command}"  -f "$header_file" -h "$header_message_id" -s send_telegram -m modify_telegram 
} } &
done 
wait
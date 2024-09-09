#!/bin/bash
#
#
# Monitors orchestrator output and sends or modify message when got test's updates
# с - REQUIRED adb command to execute and monitor it output
# s - OPTIONAL send_message fun; if not set will be used default_send_message
# m - OPTIONAL modify_message fun; if not set will be used default_modify_message
# f - OPTIONAL header status file; In case if you have multi-device run better to keep header info in file
# h - OPTIONAL/REQUIRED(if -f is set) header timestamp; will used as header message and thread main
#
# Example:
# monitor-output.sh -c "adb shell 'CLASSPATH=$(pm path androidx.test.services) app_process / \
#         androidx.test.services.shellexecutor.ShellMain am instrument -r -w \
#         -e annotation {io.annotation.Example} \
#         -e numShards \"5\" \
#         -e shardIndex \"1\" \
#         -e targetInstrumentation {io.app.test.package}/{io.runner.package} \
#         androidx.test.orchestrator/.AndroidTestOrchestrator'" -s send_message_fun -m modify_message_fun -f "header_status_file.txt" -h "1725355725.965819"
#
# set -x # Enable for debug mode

# Set params below if you use default_send_message or default_modify_message from this file
# Recommended to keep all secrets in github secrets and put here with call arguments
default_slack_api_key="xoxb-3059311361079-7657686256662-r2cAQpY1ydEhgNtyzOQDrqAt"   # Change to your slack token 
default_slack_channel_id="C07KX3P797T"                                              # Change to your slack channel id

usage() {
    echo "Usage: $0 -c <adb_command> [ -s <send_message_fun> ] [ -m <modify_message_fun> ] [ -f <status_file> ] [ -h <header_message_timestamp> ]"
    exit 1
}

while getopts "c:s:m:f:h:" opt; do
    case $opt in
        c)
            adb_command="$OPTARG"
            ;;
        s)
            send_message="$OPTARG"
            ;;
        m)
            modify_message="$OPTARG"
            ;;
        f)  
            status_file="$OPTARG"
            ;;    
        h)  
            header_message_timestamp="$OPTARG"
            ;;    
        *)
            usage
            ;;
    esac
done


# Validate command is not empty
if [ -z "$adb_command" ]; then
    usage
    exit 1
fi

# Validate status_file and header_message_timestamp must be set together
if [ ! -z "$status_file" ] || [ ! -z "$header_message_timestamp" ]; then
    if [ -z "$status_file" ] || [ -z "$header_message_timestamp" ]; then
        echo "status_file and header_message_timestamp must be set together"
        echo "status_file: $status_file"
        echo "header_message_timestamp: $header_message_timestamp"
        exit 1
    fi
fi       

# Device settings
# Gets device id from $adb_command; use case if multi-device run
device_id=$(echo "$adb_command" | sed -n 's/.*-s \([^ ]*\).*/\1/p') || true


# Context variables
class_value=""          # variable to keep class name
last_class_value=""     # variable to keep last class name
test_value=""           # variable to keep test name
last_test_value=""      # variable to keep last test name
current_value=""        # variable to keep current test number
last_current_value=""   # variable to keep last current test number
numtests_value=""       # variable to keep total count of tests in run
code_value=""           # variable to keep code status
stack_value=""          # variable to keep error stack value
message_text=""         # variable for a message text
message_ts=""           # variable for a sent message timestamp

# ---- FORMATTING RULES ----
# By default will cut all package info except class name
# For example if your test class is io.my.path.to_class.ClassName, the result will be ClassName
class_base_regex=".*\."
stack_format_start="{"      # for slack recommends to use \'\'\'; for telegram you can choose your fav, default is {
stack_format_end="}"        # for slack recommends to use \'\'\'; for telegram you can choose your fav, default is }

# Start of status message
header_status_running="RUNNING.."   # Basic status for device during test run
header_status=" STATUS: "           # Status text

# Orchestrator regexes
# Docs: https://github.com/android/android-test/blob/main/runner/android_test_orchestrator/java/androidx/test/orchestrator/listeners/OrchestrationResultPrinter.java
regex_base_start="s/.*"                                                         # Recommends to keep it default
regex_base_end="\([^ ]*\).*/\1/p"                                               # Recommends to keep it default
regex_class="$regex_base_start""class=""$regex_base_end"                        # Recommends to keep it default
regex_current="$regex_base_start""current=""$regex_base_end"                    # Recommends to keep it default
regex_numtests="$regex_base_start""numtests=""$regex_base_end"                  # Recommends to keep it default
regex_test="$regex_base_start""test=""$regex_base_end"                          # Recommends to keep it default
regex_code="$regex_base_start""INSTRUMENTATION_STATUS_CODE: \([-0-9]*\).*/\1/p" # Recommends to keep it default

# Orchestrator code statuses
# Docs: https://github.com/android/android-test/blob/main/runner/android_test_orchestrator/java/androidx/test/orchestrator/listeners/OrchestrationResultPrinter.java
code_in_progress="1"    # Orchestator status code for in progress test
code_done="0"           # Orchestator status code for passed test
code_failed="-2"        # Orchestator status code for failed test
code_ignored="-3"       # Orchestator status code for skipped test

# Message's test statuses
# You can customize it here
test_status_in_progress="⏳"
test_status_done="✅"
test_status_failed="❌"
test_status_ignored="🚧"

# Total count message sign
total_sign="▶️"

# Variables for keep count of tests
total_passed=0
total_failed=0
total_ignored=0

# Returns customized status for a orchestrator code
# $1 = orchestrator code
# example: get_test_status "-1"
# Docs: https://github.com/android/android-test/blob/main/runner/android_test_orchestrator/java/androidx/test/orchestrator/listeners/OrchestrationResultPrinter.java
get_test_status() {
    local orchestrator_code="$1"
    case "$orchestrator_code" in
        "$code_failed")
            echo "$test_status_failed"
            ;;
        "$code_done")
            echo "$test_status_done"
            ;;
        "$code_in_progress")
            echo "$test_status_in_progress"
            ;;
        "$code_ignored")
            echo "$test_status_ignored"
            ;;
        *)
            echo "Unknown status"
            ;;
    esac
}

# Extracts value from orchestrator log line
# $1 = orchestrator line
# $2 = key for search
# example: extract_value "$line" "class"
# Docs: https://github.com/android/android-test/blob/main/runner/android_test_orchestrator/java/androidx/test/orchestrator/listeners/OrchestrationResultPrinter.java
extract_value() {
    local line="$1"
    local key="$2"
    local regex="$regex_base_start$key=$regex_base_end"
    echo "$line" | sed -n "$regex"
}

# Default implementation of send_message fun for slack
# $1 - message to send
# Must return sent_message timestamp
default_send_message() {
    ./send_slack.sh "$1" "$default_slack_api_key" "$default_slack_channel_id" "$header_message_timestamp"
    wait
}

# Default implementation modify_message fun for slack
# $1 - new message text
# $2 - message_ts/message_id of message for edit
default_modify_message() {
    ./modify_slack.sh "$1" "$2" "$default_slack_api_key" "$default_slack_channel_id"
    wait
}

# If send or modify message fun not set, use default implementation
if [ -z "$send_message" ]; then
    send_message="default_send_message"
fi

if [ -z "$modify_message" ]; then
    modify_message="default_modify_message"
fi

# Processes orchestrator log line
# Works line-by-line collecting information
# When collected class+test+status info - generates message
# If message_ts does not exists then calls send_message and keep message_ts 
# Else calls modify_message with new text
# After the call resets context variables and keeps last values
# $1 - orchestrator log line
process_line() {
    local line="$1"
        # Check what is line contains
        if [[ "$line" == *"class="* ]]; then
            class_value=$(extract_value "$line" "class")
        fi

        if [[ "$line" == *"current="* ]]; then
            current_value=$(extract_value "$line" "current")
        fi

        if [[ "$line" == *"numtests="* ]]; then
            numtests_value=$(extract_value "$line" "numtests")
        fi

        if [[ "$line" == *"test="* ]]; then
            test_value=$(extract_value "$line" "test")
        fi

        if [[ "$line" == *"stack="* ]]; then
            stack_value=$(echo "$line" | sed -n "s/.*stack=\(.*\)/\1/p")
        fi

        if [[ "$line" == *"INSTRUMENTATION_STATUS_CODE:"* ]]; then
            code_value=$(echo "$line" | sed -n "$regex_code")
        fi

        # Checks if full information about running test collected
        if [[ -n "$class_value" && -n "$current_value" && -n "$numtests_value" && -n "$test_value" && -n "$code_value" ]]; then

            # Regex class value
            class_value=$(echo "$class_value" | sed "s|$class_base_regex||")

            # Gets test displaying status
            test_status=$(get_test_status "$code_value")

            # Concats class, test and status
            message=$(echo "$class_value.$test_value $test_status")

            # If test is failed then adds stack to the message
            if [[ "$test_status" = "$test_status_failed" ]]; then
              message+="$stack_format_start$stack_value$stack_format_end"
            fi

            # Gets test count
            testsCount=$(echo "$current_value/$numtests_value")

            # Creates statuses tests count
            case "$test_status" in
                "$test_status_failed")
                    total_failed=$(( $total_failed + 1 ))
                    ;;
                "$test_status_done")
                    total_passed=$(( $total_passed + 1 ))
                    ;;
                "$code_in_progress")
                    echo "$test_status_in_progress"
                    ;;
                "$test_status_ignored")
                    total_ignored=$(( $total_ignored + 1 ))
                    ;;
            esac

            # Gets tests run total info
            count_message="$total_sign:$numtests_value"
            if [ "$total_passed" -gt 0 ]; then
              count_message+=" $test_status_done:$total_passed"
            fi
            if [ "$total_failed" -gt 0 ]; then
              count_message+=" $test_status_failed:$total_failed"
            fi
            if [ "$total_ignored" -gt 0 ]; then
              count_message+=" $test_status_ignored:$total_ignored"
            fi    

            # If header is not set yet, sets it by device_id and header text concat
            if [[ -z "$header" ]]; then
                header="$device_id$header_status"
            fi

            # If status_file in use then updates run info in the file
            if [[ ! -z "$status_file" ]]; then
                sed -i '' "s/^$header.*/$header$header_status_running$count_message/" "$status_file"
                # If message_text wasn't set then set it as device_id if available
                if [[ -z "$message_text" ]]; then 
                    message_text="$device_id"
                fi
                # Calls modify message with run status_file info and header_message_timestamp
                echo $($modify_message "$(cat $status_file)" "$header_message_timestamp")
            # If no using status_file then updates run info in the message    
            else
                # If message_text wasn't set then set is as header and run info
                if [[ -z "$message_text" ]]; then 
                    message_text="$header$count_message"
                else 
                # If was, updates run info in message's header
                    message_text=$(echo "$message_text" | sed "s/^$header.*/$header$count_message/")
                fi
            fi
            
            # If current test = last one then updates last line in the message_text
            if [[ "$last_current_value" == "$current_value" && "$last_class_value" == "$class_value" && "$last_test_value" == "$test_value" ]]; then
                message_text=$(printf "%s\n%s" "$(echo "$message_text" | sed '$d')" "$message")
            # Else adds new line to the message_text  
            else
                message_text=$(printf "%s\n%s" "$message_text" "$message" "$testsCount")
            fi

            echo "TEST_RESULTS: $message_text" # Optional, provides more readable logs

            # Checks if message's timestamp exists
            # If not exists - send new message and save it's timestamp
            if [[ -z "$message_ts" ]]; then
              message_ts=$($send_message "$message_text")
              echo "Message ts: $message_ts"
            # If exists - modify sent message by timestamp  
            else
              echo $($modify_message "$message_text" "$message_ts")
              wait
            fi

            # Keep last values
            last_current_value=$current_value
            last_class_value=$class_value
            last_test_value=$test_value

            # Resets current context values
            class_value=""
            current_value=""
            numtests_value=""
            test_value=""
            code_value=""
            test_status=""

            # Optional sleep for debug, uncomment if needed
            sleep 1
        fi
}


# Fun to eval and monitor orchestrator log
monitor() {
    eval "$adb_command" | while IFS= read -r line; do
        process_line "$line"
    done
}

# Entry point
monitor
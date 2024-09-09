# android-orchestrator-reporter
Tools for reporting during android orchestrator run

main.apk - example target test apk built by ./gradlew assemble
test.apk - emample apk with instrumented tests; contains 2 passed 2 failed and 1 skipped tests built by ./gradlew assembleAndroidTest

monitor-output.sh - main script for monitoring orchestrator output and build readable test result messages
call-output.sh - example script to call monitor-output.sh with run params

send_slack.sh - example of implementation send message to slack
modify_slack.sh - example of implementation modify message on slack

send_telegram.sh - example of implementation send message to telegram
modify_telegram.sh - example of implementation edit message in telegram

orchestrator-1.5.0-alpha01.apk - android orchestrator apk
test-services-1.5.0-alpha01.apk - android test-services apk



For usage you can set required params in monitor-output and call-output (if you wanna use it) and then just use ./call-output.sh for start tests
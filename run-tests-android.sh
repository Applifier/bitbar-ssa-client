#!/bin/bash

# Set environment variable to let test scripts know that this is a testdroid run
export TESTDROID=1

TEST=${TEST:="your_test.js"} #Name of the test file

##### Cloud testrun dependencies start
echo "Extracting tests.zip..."
unzip tests.zip

echo "Starting Appium ..."
/opt/appium/appium/bin/appium.js --log-no-colors --log-timestamp >appium.log 2>&1 &

sleep 5 # Sleep for appium to launch properly

##### Cloud testrun dependencies end.

export APPIUM_APPFILE=$PWD/application.apk #App file is at current working folder

## Run the test:
echo "Running test ${TEST}"
rm -rf screenshots
mkdir screenshots

source 'run-tests-android.sh'

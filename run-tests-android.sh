#!/bin/bash

# Set environment variable to let test scripts know that this is a testdroid run
export TESTDROID=1

TEST=${TEST:="your_test.js"} #Name of the test file

##### Cloud testrun dependencies start
echo "[Testdroid-ssa-client] Extracting tests.zip..."
unzip tests.zip

echo "[Testdroid-ssa-client] NOT Starting Appium, start it in your test script if needed!"

##### Cloud testrun dependencies end.

export APPIUM_APPFILE=$PWD/application.apk #App file is at current working folder

## Run the test:
echo "[Testdroid-ssa-client] Running test ${TEST}"
rm -rf screenshots
mkdir screenshots

source 'run-tests-android.sh'

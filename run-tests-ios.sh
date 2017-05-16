#!/bin/bash

# Set environment variable to let test scripts know that this is a testdroid run
export TESTDROID=1

TEST=${TEST:="your_test.js"} #Name of the test file

##### Cloud testrun dependencies start
echo "Extracting tests.zip..."

unzip tests.zip

echo "Starting Appium ..."
/opt/appium/bin/appium.js -U ${UDID} --command-timeout 120 --log-no-colors --log-timestamp >appium.log 2>&1 &

echo -n "Waiting for Appium server to be ready "
start_string="Appium REST http interface listener started"
retry=30
while [ $retry -gt 0 ]
do
  sleep 1
  echo -n "."
  if [ -n "$(grep -s "$start_string" appium.log)" ]; then
    retry=0
    echo " done"
    echo $(grep "$start_string" appium.log)
  else
    ((retry--))
    if [ $retry -eq 0 ]; then
      echo " waited 30 seconds but server was not ready"
    fi
  fi
done

export APPIUM_APPFILE=$PWD/application.ipa #App file is at current working folder

## Run the test:
echo "Running test ${TEST}"
rm -rf screenshots
mkdir screenshots

source 'run-tests-ios.sh'

#!/bin/bash
# Start appium test on testdroid using
# "Parallel-test-runs"-API, aka "Server-side-appium-tests"
# Requires: jq (cmdline json parser)

# Configure statically
#PROJECT_NAME="Appium Server Side Demo"
TEST_RUN_NAME="Server Side cmdline Demo"

ios_start_script='run-tests-ios.sh'
android_start_script='run-tests-android.sh'
generic_start_script='run-tests.sh'

# Work from this directory
cd "$(dirname "$0")" || exit

# Consts
CLEANUP_FILES=(
  'node_modules'
  'screenshots'
  'TEST-all.xml'
  'logcat.log'
  'console.log'
  'syslog.log'
)
TD_CLOUD_BASE_URL="https://cloud.testdroid.com"
TD_TOKEN_URL="${TD_CLOUD_BASE_URL}/oauth/token"
TD_PROJECTS_URL="${TD_CLOUD_BASE_URL}/api/v2/me/projects"
TD_USER_DEVICE_GROUPS_URL="${TD_CLOUD_BASE_URL}/api/v2/me/device-groups"
TD_PROJECT_DEVICE_GROUPS_URL_TEMPLATE="${TD_CLOUD_BASE_URL}/api/v2/me/projects/<projectId>/device-groups"
TD_UPLOAD_APP_URL_TEMPLATE="${TD_CLOUD_BASE_URL}/api/v2/me/projects/<projectId>/files/application"
TD_UPLOAD_TEST_URL_TEMPLATE="${TD_CLOUD_BASE_URL}/api/v2/me/projects/<projectId>/files/test"
TD_CONFIGURE_PROJECT_URL_TEMPLATE="${TD_CLOUD_BASE_URL}/api/v2/me/projects/<projectId>/config"
TD_TEST_RUNS_URL_TEMPLATE="${TD_CLOUD_BASE_URL}/api/v2/me/projects/<projectId>/runs"
TD_TEST_RUN_ITEM_URL_TEMPLATE="${TD_TEST_RUNS_URL_TEMPLATE}/<runId>"
TD_TEST_DEVICE_RUN_URL_TEMPLATE="${TD_TEST_RUN_ITEM_URL_TEMPLATE}/device-runs"
TD_TEST_RUN_ITEM_BROWSER_URL_TEMPLATE="https://cloud.testdroid.com/#service/testrun/<projectId>/<runId>"
TD_DEFAULT_HEADER="Accept: application/json"
TEST_ZIP_FILE='test.zip'
CURL_SILENT=" -s "
TOKEN_TMP_FILE="_token.json"
PLATFORM="NOT-SET"
SIMULATE=0
SCHEDULER="PARALLEL"
PROJECT_TIMEOUT=600
FAIL_PASSED_THRESHOLD=0
DEVICES_RUN_THRESHOLD=0
CONNECTION_FAILURES_LIMIT=20

# Helper Functions
function usage(){
  echo -e "usage:\n   $0 OPTIONS"
  echo -e "OPTIONS:"
  echo -e "\t -h\tShow this message"
  echo -e "\t -z\tThe tests-folder which will be archived and sent to testdroid (required)"
  echo -e "\t -u\tUsername (required, can also use API-key here)"
  echo -e "\t -p\tPassword (required unless using API-key)"
  echo -e "\t -t\tTestdroid project name (required)"
  echo -e "\t -a\tApp build file to test (apk/ipa) (required, also selects platform)"
  echo -e "\t -r\tTestdroid test run name"
  echo -e "\t -d\tTestdroid deviceGroup ID to use (default: previous one)"
  echo -e "\t -l\tList Testdroid deviceGroups"
  echo -e "\t -s\tSimulate (Upload tests and app and configure project. Don't actually run test)"
  echo -e "\t -c\tSet scheduler for test, options are [PARALLEL, SERIAL, SINGLE] (default: PARALLEL)"
  echo -e "\t -i\tSet timeout value for project in seconds. Will use 600s (10min) unless specified"
  echo -e "\t -f\tSet fail threshold in percentage [0-100], the percentage of test steps that have to pass for the test run to succeed (impacts exit value)"
  echo -e "\t -x\tSet device completion threshold in percentage [0-100], the percentage of devices in device group that need to complete for the test run to complete (impacts exit value)"
  echo -e "\t -v\tVerbose"
  echo -e "Example:"
  echo -e "\t$0 -u you@yourdomain.com -p hunter2 -t \"Example test Project\" -r \"Nightly run, Monday\" -a path/to/build.apk"
}

function verbose() {
  set -o xtrace
  CURL_SILENT=""
}

function get_full_path {
  echo "$( cd "$(dirname "$1")"; echo "$(pwd)/$(basename "$1")" )"
}

function prettyp {
  echo -e "[$(date +"%T")] $1"
}

function rational_to_percent {
  echo "$(echo "$1*100"|bc)"
}

function authenticate {
  # Get token for testdroid
  # Don't log in if using token (no password specified)
  if [ -n "$PASSWORD" ]; then
    auth_curl_data="client_id=testdroid-cloud-api&grant_type=password&username=${TD_USER}"
      auth_curl_data="${auth_curl_data}&password=${PASSWORD}"
    curl ${CURL_SILENT} -X POST -H "${TD_DEFAULT_HEADER}" -d "${auth_curl_data}" $TD_TOKEN_URL > "${TOKEN_TMP_FILE}"
    auth_error=$(jq '.error_description' "${TOKEN_TMP_FILE}")
    if [ "${auth_error}" != "null" ]; then echo "ERROR LOGGING IN! '${auth_error}'. Please check credentials" ; exit 1 ; fi
  fi
}

function get_token {
  if [ ! -f $TOKEN_TMP_FILE ]; then
    authenticate
  fi
  access_token=$(jq -r '.access_token' $TOKEN_TMP_FILE)
  refresh_token=$(jq -r '.refresh_token' $TOKEN_TMP_FILE)
  # token should be refreshed when it's half way done
  refresh_token_after=$(echo "$(date +"%s") + $(echo "$(jq '.expires_in' $TOKEN_TMP_FILE)/2" |bc)" |bc)

  # Refresh token if needed
  if [ "$(date +"%s")" -gt "$refresh_token_after" ]; then
    refresh_auth_curl_data="client_id=testdroid-cloud-api&grant_type=refresh_token&refresh_token=${refresh_token}"
    curl ${CURL_SILENT} -X POST -H "${TD_DEFAULT_HEADER}" -d "${refresh_auth_curl_data}" $TD_TOKEN_URL > "${TOKEN_TMP_FILE}"
    access_token=$(jq -r '.access_token' $TOKEN_TMP_FILE)
    refresh_token=$(jq -r '.refresh_token' $TOKEN_TMP_FILE)
    refresh_token_after=$(echo "$(date +"%s") + $(echo "$(jq '.expires_in' $TOKEN_TMP_FILE)/2" |bc)" |bc)
    if [ "$access_token" == "null" ]; then
      echo "Bad access token, check credentials: '${access_token}'"
      exit 3
    fi
  fi

  if [ "$access_token" == "null" ]; then
    prettyp "Bad access token, check credentials: '${access_token}'"
    exit 3
  fi
  echo "$access_token"
}

########################################
# Authenticates using either username + password
# OR API key and sets default values for curl-call
# Arguments:
#   Any additional curl switches and options
# Returns:
#   response (String)
#########################################

function auth_curl {
  if [ -n "$PASSWORD" ]; then
    project_listing_header="Authorization: Bearer $(get_token)"
    curl ${CURL_SILENT} -H "${TD_DEFAULT_HEADER}" -H "${project_listing_header}" "$@"
  else
    # Reason for ':' in -u flag: user:password but with password left empty
    curl ${CURL_SILENT} -H "${TD_DEFAULT_HEADER}" -u "${TD_USER}:" "$@"
  fi
}

########################################
# Create an url from an url template
# Globals:
#   PROJECT_ID
# Arguments:
#   test_run_id (optional)
# Returns:
#   url (String)
#########################################
function url_from_template {
  template=$1
  project_id=$PROJECT_ID
  if [ -z "${project_id}" ]; then
    project_id=$(get_project_id "$PROJECT_NAME")
  fi
  test_run_id=$2
  sed -e "s/<runId>/${test_run_id}/" -e "s/<projectId>/${project_id}/" <<< "${template}"
}

########################################
# Fetch project_id for defined project name
# Arguments:
#   project_name
# Returns:
#   project_id (sets PROJECT_ID env variable)
#########################################
function get_project_id {
  project_name=$1
  PROJECT_ID=$(auth_curl "${TD_PROJECTS_URL}" | jq ".data[] | select(.name==\"${project_name}\") | .id")
  if [ -z "${PROJECT_ID}" ]; then
    echo "Cannot read project_id for project '$project_name'"
    exit 88
  fi
  echo "$PROJECT_ID"
}

########################################
# Print TD device groups
# Globals:
#   PROJECT_ID
# Arguments:
#   None
# Returns:
#   Void (prints device groups)
#########################################
function list_device_groups {
  device_group_url=$(url_from_template "${TD_PROJECT_DEVICE_GROUPS_URL_TEMPLATE}")
  prettyp "Device groups for project: $(auth_curl "${device_group_url}" |jq "")"
  prettyp "Device groups for user: $(auth_curl "${TD_USER_DEVICE_GROUPS_URL}" |jq "")"
}

########################################
# Upload test application to cloud
# Arguments:
#   full_app_path
# Returns:
#   Void
#########################################
function upload_app_to_cloud {
  full_app_path=$1
  td_upload_url=$(url_from_template "${TD_UPLOAD_APP_URL_TEMPLATE}")
  response=$(auth_curl -POST -F file=@"${full_app_path}" "${td_upload_url}")
  app_upload_id=$(echo "$response" | jq '.id')
  if [ -z "$app_upload_id" ]; then
    prettyp "ERROR: Uploading of app failed. Response was: \"$response\""
    exit 4
  fi
  if [ "$app_upload_id" == "null" ]; then
    prettyp "ERROR: Uploading of app failed. Response was: \"$response\""
    exit 4
  fi
  prettyp "Uploaded \"${full_app_path}\""
}

########################################
# Upload test script archive to cloud
# Arguments:
#   full_test_path
# Returns:
#   Void
#########################################
function upload_test_archive_to_cloud {
  full_test_path=$1
  td_upload_url=$(url_from_template "${TD_UPLOAD_TEST_URL_TEMPLATE}")
  response=$(auth_curl -POST -F file=@"${full_test_path}" "${td_upload_url}")
  test_upload_id=$(echo "$response" | jq '.id')
  if [ -z "$test_upload_id" ]; then
    prettyp "ERROR: Uploading of app failed. Response was: \"$response\""
    exit 5
  fi
  if [ "$test_upload_id" == "null" ]; then
    prettyp "ERROR: Uploading of app failed. Response was: \"$response\""
    exit 5
  fi
  prettyp "Uploaded \"${full_test_path}\""
}

########################################
# Setup project for requested device group,
# device scheduler and project timeout
# Arguments:
#   device_group_id
# Returns:
#   Void
#########################################
function setup_project_settings {
  device_group_id=$1
  project_config_url=$(url_from_template "${TD_CONFIGURE_PROJECT_URL_TEMPLATE}")
  flags_to_alter="-F scheduler=${SCHEDULER:?} -F timeout=${PROJECT_TIMEOUT:?}"
  if [ -z "$DEVICE_GROUP_ID" ]; then
    prettyp "Device group id not specified, using previous value"
  else
    flags_to_alter="${flags_to_alter} -F usedDeviceGroupId=${device_group_id}"
  fi
  response=$(auth_curl -POST ${flags_to_alter} "${project_config_url}")
  used_device_group_id=$(echo "$response" | jq '.usedDeviceGroupId')
  used_scheduler=$(echo "$response" | jq -r '.scheduler')
  used_project_timeout=$(echo "$response" | jq -r '.timeout')
  if [ -n "$DEVICE_GROUP_ID" ]; then
    if [ "$used_device_group_id" == "$device_group_id" ]; then
      prettyp "Using device group $used_device_group_id"
    else
      prettyp "Unable to set device group id for project! Exiting. Response was '$response'"
      exit 11
    fi
  fi
  if [ "$used_scheduler" == "$SCHEDULER" ]; then
    prettyp "Using scheduler '$used_scheduler'"
  else
    prettyp "Unable to set scheduler '${SCHEDULER}' for project! Exiting. Response was '$response'"
    exit 11
  fi
  if [ "$used_project_timeout" == "$PROJECT_TIMEOUT" ]; then
    prettyp "Using timeout '$used_timeout'"
  else
    prettyp "Unable to set timeout '${PROJECT_TIMEOUT}' for project! Exiting. Response was '$response'"
    exit 11
  fi
}

########################################
# Start test run
# Arguments:
#   test_run_name
# Returns:
#   test_run_id
#########################################
function start_test_run {
  test_run_name=$1
  test_runs_url=$(url_from_template "${TD_TEST_RUNS_URL_TEMPLATE}")
  response=$(auth_curl -POST -F name="${test_run_name}" "${test_runs_url}")
  test_run_id=$(echo "$response" | jq '.id')
  if [ -z "$test_run_id" ]; then
    prettyp "Did not get a test_run_id. Maybe test didn't start? Response was '$response'"
    exit 6
  fi
  echo "$test_run_id"
}

########################################
# Get human readable name for device
# Arguments:
#   test_run_id
#   device_run_id
# Returns:
#   String (human readable device id (or device_run_id if failure))
#########################################
function get_device_human_name {
  test_run_id="$1"
  device_run_id="$2"
  test_run_item_url=$(url_from_template "${TD_TEST_RUN_ITEM_URL_TEMPLATE}" "${test_run_id}")
  device_info_url="$test_run_item_url/device-runs/$device_run_id"
  device_info_json=$(auth_curl "$device_info_url" --fail)
  human_name=$(echo "$device_info_json" |jq -r '.deviceName + "-API\(.softwareVersion.apiLevel)"' |sed -e s/[^a-zA-Z0-9_-]/_/g)
  safe_human_name=$(sed -e s/[^a-zA-Z0-9_-]/_/g <<< "$human_name")
  safe_human_name=${safe_human_name:=$device_run_id}
  echo "$safe_human_name-$device_run_id"
}


########################################
# Get all test results and files
# Arguments:
#   test_run_id
# Returns:
#   Void (writes files to subfolder 'results/')
#########################################
function get_result_files {
  echo "let's do this"
  test_run_id=$1
  device_runs_url=$(url_from_template "${TD_TEST_DEVICE_RUN_URL_TEMPLATE}" "${test_run_id}")
  response=$(auth_curl "${device_runs_url}")
  device_run_ids=$(echo "$response" | jq '.data[].id')
  for device_run_id in $device_run_ids; do
    get_device_result_files "$test_run_id" "$device_run_id"
  done
}


########################################
# Get all test results and files for the device
# Arguments:
#   test_run_id
#   device_run_id
# Returns:
#   Void (writes files to subfolder 'results/')
#########################################
function get_device_result_files {
  mkdir -p "results"
  test_run_id="$1"
  device_run_id="$2"
  test_run_item_url=$(url_from_template "${TD_TEST_RUN_ITEM_URL_TEMPLATE}" "${test_run_id}")
  device_info_url="$test_run_item_url/device-runs/$device_run_id"
  device_session_id=$(auth_curl "$device_info_url" | jq ".deviceSessionId")
  device_human_name="$(get_device_human_name "$test_run_id" "$device_run_id")"
  device_session_files_url="$test_run_item_url/device-sessions/$device_session_id/output-file-set/files"
  response=$(auth_curl "$device_session_files_url")
  device_file_ids=$(echo "$response" | jq '.data[] |"\(.id);\(.name)"')
  for file_specs in $device_file_ids; do
    get_device_result_file "$test_run_id" "$device_run_id" "$device_human_name" "$file_specs"
  done
}

########################################
# Get a device result file
# Arguments:
#   test_run_id
#   device_run_id
#   device_human_name
#   semicolon-separated string like "$file_id;$filename"
# Returns:
#   Void (writes files to subfolder 'results/')
#########################################
function get_device_result_file {
  test_run_id="$1"
  device_run_id="$2"
  device_human_name="$3"
  file_id=$(sed -e 's/"//g' -e 's/;.*//g' <<< "$4")
  filename=$(sed -e 's/"//g' -e 's/.*;//g' <<< "$4")
  file_item_url="${TD_CLOUD_BASE_URL}/api/me/files/$file_id/file"
  auth_curl "$file_item_url" --fail --output "results/${device_run_id}_${device_human_name}_$filename"
}


# Commandline arguments
while getopts hvslu:p:t:r:a:d:c:i:f:x:z: OPTIONS; do
  case $OPTIONS in
    z ) TEST_ARCHIVE_FOLDER=$OPTARG ;;
    u ) TD_USER=$OPTARG ;;
    p ) PASSWORD=$OPTARG ;;
    t ) PROJECT_NAME=$OPTARG ;;
    r ) TEST_RUN_NAME=$OPTARG ;;
    a ) APP_PATH=$OPTARG ;;
    d ) DEVICE_GROUP_ID=$OPTARG ;;
    l ) LIST_DEVICES_ONLY=1 ;;
    c ) SCHEDULER=$OPTARG ;;
    i ) PROJECT_TIMEOUT=$OPTARG ;;
    s ) SIMULATE=1 ;;
    f ) FAIL_PASSED_THRESHOLD=$OPTARG ;;
    x ) DEVICES_RUN_THRESHOLD=$OPTARG ;;
    h ) usage; exit ;;
    v ) verbose ;;
    \? ) echo "Unknown option -$OPTARG" >&2 ; exit 1;;
    : ) echo "Missing required argument for -$OPTARG" >&2 ; exit 1;;
  esac
done

# Check args
if [ -z "${TD_USER}" ]; then echo "Please specify username!" ; usage ; exit 1 ; fi
if [ -z "${PROJECT_NAME}" ]; then echo "Please specify testdroid project name!" ; usage ; exit 1 ; fi
if [ "${LIST_DEVICES_ONLY}" == "1" ]; then list_device_groups ; exit 0 ; fi
if [ -z "${APP_PATH}" ]; then echo "Please specify app path!" ; usage ; exit 1 ; fi
if [ -z "${TEST_ARCHIVE_FOLDER}" ]; then echo "Please specify the folder containing the tests!" ; usage ; exit 1 ; fi

# Check that test_application is given as parameter
if [ -z APP_PATH ]; then
  echo "Please specify the test_application as an argument"
  echo -e "$(usage)"
  exit 1
else
  orgdir=$(pwd)
  FULL_APP_PATH=$(get_full_path "${APP_PATH}")
  cd "$orgdir" || exit 33
  if [ ! -f "${FULL_APP_PATH}" ]; then
    echo "App file '${APP_PATH}' does not exist!"
    exit 2
  fi
  extension=${FULL_APP_PATH##*.}
  case "${extension}" in
    "apk" )
      PLATFORM="android" ;;
    "ipa" | "app" )
      PLATFORM="ios" ;;
    * )
      prettyp "Cannot handle unexpected platform with extension ${extension}"
      exit 12 ;;
  esac
fi

# Check that test folder exists and is a folder
if [ ! -d "${TEST_ARCHIVE_FOLDER}" ]; then
  echo "Test folder does not exist! Gave path '${TEST_ARCHIVE_FOLDER}'"
  exit 13
fi

# Check dependencies
which jq
if [ $? -ne 0 ]; then echo "Please install 'jq' before running script." ; usage ; exit 101; fi
which zip
if [ $? -ne 0 ]; then echo "Please install 'zip' before running script." ; usage ; exit 102; fi
which curl
if [ $? -ne 0 ]; then echo "Please install 'curl' before running script." ; usage ; exit 103; fi
which bc
if [ $? -ne 0 ]; then echo "Please install 'bc' before running script." ; usage ; exit 104; fi

# Create test.zip
mv ${TEST_ZIP_FILE} test_previous.zip
zip_temp_dir="testzip"
rm -rf "${zip_temp_dir:?}"
cp -rf "${TEST_ARCHIVE_FOLDER:?}" "${zip_temp_dir:?}"
for i in "${CLEANUP_FILES[@]}"; do
  rm -rf "${zip_temp_dir:?}/${i:?}"
done

cd $zip_temp_dir || exit 34

if [ ! -f "$generic_start_script" ]; then
  case "${PLATFORM}" in
    "android")
      cp "../$android_start_script" "$generic_start_script" ;;
    "ios")
      cp "../$ios_start_script" "$generic_start_script" ;;
    *) prettyp "Unknown platform '$PLATFORM'" ; exit 14 ;;
  esac
fi

zip ${TEST_ZIP_FILE} -r ./*
mv ${TEST_ZIP_FILE} ..
cd ..

FULL_TEST_PATH=$(get_full_path $TEST_ZIP_FILE)

# Get PROJECT_ID
get_project_id "$PROJECT_NAME"

# Upload app to testdroid cloud
upload_app_to_cloud "$FULL_APP_PATH"

# Upload test-archive to testdroid cloud
upload_test_archive_to_cloud "$FULL_TEST_PATH"

# Configure project (device_group_id)
setup_project_settings "$DEVICE_GROUP_ID"

if [ "$SIMULATE" -eq "1" ]; then
  prettyp "Simulated run, not actually starting test" ; exit 0
fi

# Start test run
test_run_id=$(start_test_run "$TEST_RUN_NAME")
echo "test_run_id='$test_run_id'"

# Get the test run device runs
device_runs_url=$(url_from_template "${TD_TEST_DEVICE_RUN_URL_TEMPLATE}" "${test_run_id}")
response=$(auth_curl "${device_runs_url}")
device_count=$(echo "$response" | jq '.total')
prettyp "Device count for test: ${device_count}"

# Get Test run status
prettyp "Test is running"
test_run_status_tmp_file="_test_run_status.json"
test_run_url=$(url_from_template "${TD_TEST_RUN_ITEM_URL_TEMPLATE}" "${test_run_id}")
test_run_browser_url=$(url_from_template "${TD_TEST_RUN_ITEM_BROWSER_URL_TEMPLATE}" "${test_run_id}")
prettyp "Results are to be found at ${test_run_browser_url}"
test_status=""
connection_failures=0
while [ 1 -ne 2 ]; do
  sleep 5

  auth_curl "${test_run_url}" > "${test_run_status_tmp_file}"
  test_status_new=$(jq '.state' $test_run_status_tmp_file |xargs)
  if [ "${test_status}" != "${test_status_new}" ]; then
    test_status=$test_status_new
    echo ; prettyp "Test status changed: $test_status"
  fi

  case "$(echo "$test_status" |xargs)" in
    "FINISHED" )
      executed_percent=$( rational_to_percent "$(jq '.executionRatio' ${test_run_status_tmp_file})")
      success_percent=$( rational_to_percent "$(jq '.successRatio' ${test_run_status_tmp_file})")
      echo ; prettyp "Test Finished!\nDevices: ${device_count}, Executed-precentage: ${executed_percent}%, Passed-percentage: ${success_percent}%, results at: ${test_run_browser_url}"
      echo ;prettyp "Getting test jUnit xml results"
      get_result_files "$test_run_id"
      if (( $(bc <<< "$FAIL_PASSED_THRESHOLD > $success_percent") )); then
        prettyp "Test failed, required a success percentage of ${FAIL_PASSED_THRESHOLD}%, test was at ${success_percent}%"
        exit 150
      fi
      if (( $(bc <<< "$DEVICES_RUN_THRESHOLD > $executed_percent") )); then
        prettyp "Test failed, required a completion percentage of ${DEVICES_RUN_THRESHOLD}%, test was at ${executed_percent}%"
        exit 151
      fi

      exit 0 ;;
    "WAITING" | "RUNNING" )
      printf "." ;;
    "null" )
      ((connection_failures+=1))
      echo ; prettyp "Error, cannot read test status, connection problem? (fail [$connection_failures/$CONNECTION_FAILURES_LIMIT])"
      if [ "$connection_failures" -gt "$CONNECTION_FAILURES_LIMIT" ]; then
        exit 7
      fi ;;
    * )
      ((connection_failures+=1))
      prettyp "Error, unexpected status for test run. Status was=\"$test_status\" (fail [$connection_failures/$CONNECTION_FAILURES_LIMIT])"
      if [ "$connection_failures" -gt "$CONNECTION_FAILURES_LIMIT" ]; then
        exit 8
      fi ;;
  esac
done

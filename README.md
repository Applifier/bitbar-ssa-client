# testdroid-ssa-client

## usage:
   ./testdroid_cmdline.sh OPTIONS
## OPTIONS:
	 -h	Show this message
	 -z	Path to the tests-folder which will be archived and sent to testdroid (required)
	 -u	Username (required, can also use API-key here)
	 -p	Password (required unless using API-key)
	 -t	Testdroid project name (required)
	 -a	App build file to test (apk/ipa) (required, also selects platform)
	 -r	Testdroid test run name
	 -d	Testdroid deviceGroup ID to use (default: previous one)
	 -l	List Testdroid deviceGroups
	 -s	Simulate (Upload tests and app and configure project. Don't actually run test)
	 -c	Set scheduler for test, options are [PARALLEL, SERIAL, SINGLE] (default: PARALLEL)
	 -i	Set timeout value for project in seconds. Will use 600s (10min) unless specified
	 -f	Set fail threshold in percentage [0-100], the percentage of test steps that have to pass for the test run to succeed (impacts exit value)
	 -x	Set device completion threshold in percentage [0-100], the percentage of devices in device group that need to complete for the test run to complete (impacts exit value)
	 -v	Verbose
## Example:
	./testdroid_cmdline.sh -u you@yourdomain.com -p hunter2 -t "Example test Project" -r "Nightly run, Monday" -a path/to/build.apk -z ../path_to_my_test_folder -c SINGLE


## For an example with test application and appium tests (mocha.js) please have a look at this repository
https://github.com/ujappelbe/testdroid-ssa-client-example

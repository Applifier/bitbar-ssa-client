# bitbar-ssa-client

## Usage
  ./testdroid_cmdline.sh OPTIONS
## Test run OPTIONS:
        -z	The tests-folder which will be archived and sent to Bitbar Cloud (required)
        -u	Username (required, can also use API-key here)
        -p	Password (required unless using API-key)
        -t	Bitbar Cloud project name (required)
        -a	App build file to test (apk/ipa) (required, also selects platform)
        -w	Framework id to be used (required, check Bitbar API for available values)
        -r	Bitbar Cloud test run name
        -d	Bitbar Cloud deviceGroup ID to use (default: previous one)
        -l	List Bitbar Cloud deviceGroups
        -s	Simulate (Upload tests and app and configure project. Don't actually run test)
        -c	Set scheduler for test, options are [PARALLEL, SERIAL, SINGLE] (default: PARALLEL)
        -i	Set timeout value for project in seconds. Will use 600s (10min) unless specified.
            NOTE: this timeout applies to a **single test run on a device**
        -x	Set timeout value for bitbar-ssa-client in seconds (no default timeout).
            NOTE: this timeout applies to the **entire run of bitbar-ssa-client**,
            devices that tests didn't start on within this timeout will be **skipped**
        -q  Set counter for auto retrying failed test runs on devices. By default failed test run is retried 3 times.

## After test run OPTIONS:
        -n	Specify a testRunId, client will only fetch those results and exit (numeric id, check test results URL)
## Misc OPTIONS
        -h	Show this message
        -v	Verbose
## Example:
        ./testdroid_cmdline.sh -u you@yourdomain.com -p hunter2 -t "Example test Project" -r "Nightly run, Monday" -a path/to/build.apk

## For an example with test application and appium tests (mocha.js) please have a look at this repository
https://github.com/ujappelbe/testdroid-ssa-client-example

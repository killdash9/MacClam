# MacClam

The Non-Graphical Antivirus Solution for Mac OS X

I wrote this as a free alternative to the excellent <a
href="https://www.clamxav.com/" target="_blank">ClamAV</a>.  MacClam
sets up real-time directory monitoring and schedules periodic scans.
It uses [ClamAV](http://www.clamav.net/) as an AntiVirus engine and
[fswatch](https://github.com/emcrisostomo/fswatch) to monitor
directories for changed files, which are then sent to clamd for
scanning.  It also provides a way to scan individual files or
directories on demand from the command line.

## Installation ##

Installation is very simple.  In a bash shell, type

    curl -O https://raw.githubusercontent.com/killdash9/MacClam/master/MacClam.sh
    chmod +x MacClam.sh
    ./MacClam.sh

This will bootstrap by installing the lastest versions of ClamAV and
fswatch.  Using crontab, it will schedule a full file system scan once
a week and check for signatures once a day.  It also sets up live
monitoring for the $HOME and /Applications directories.  Each of these
things can be configured by modifying script variables and running it
again.

## Usage ##

Run `./MacClam.sh` with no arguments at any time to check for updates to
software or virus signatures.  Run it with file or directory arguments
to manually scan those files or directories.

## Customization ##

Scheduled scans, monitoring and installation location can be
configured by editing configuration variables at the beginning of the
script, and then running the script again to apply your changes.

## Design Principle ##

The script is designed to have a very simple interface -- one command
to do everything.  The command is idempotent, meaning that re-running
the command will do nothing if everything is set up correctly and
services are running.  If there are changes in the configuration
variables, it will make sure they are applied, and restart services as
necessary.

## TODO ##
* "Run on Startup" functionality
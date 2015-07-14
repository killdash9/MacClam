# MacClam

The Non-Graphical Antivirus Solution for Mac OS X

I wrote this as a free alternative to the excellent <a
href="https://www.clamxav.com/" target="_blank">ClamXav</a>.  MacClam
sets up real-time directory monitoring and schedules periodic scans.
It uses <a href="http://www.clamav.net/" target="_blank">ClamAV</a> as
an AntiVirus engine and <a
href="https://github.com/emcrisostomo/fswatch"
target="_blank">fswatch</a> to monitor directories for changed files,
which are then sent to clamd for scanning.  It also provides a way to
scan individual files or directories on demand from the command line.

## Prerequisites ##

You will need to have Apple's <a
href="https://developer.apple.com/library/ios/technotes/tn2339/_index.html">Xcode
command line tools</a> installed.

## Installation ##

Installation is very simple.  In a bash shell, type

    curl -O https://raw.githubusercontent.com/killdash9/MacClam/master/MacClam.sh
    chmod +x MacClam.sh
    ./MacClam.sh

This will bootstrap MacClam by building the lastest versions of ClamAV
and fswatch from source.  It will schedule a full file system scan
once a week and update signatures once a day.  It also sets up live
monitoring for the $HOME and /Applications directories.  Each of these
things can be configured by modifying script variables and re-running
the script.

## Usage ##

`./MacClam.sh` does the following:

* Builds clamd and fswatch from source if needed
* Schedules regular signature updates and full scans in crontab
* Updates clamd signatures
* Starts live monitoring services clamd and fswatch if not already running

`./MacClam.sh /path/to/file_or_directory`

Does everything previously listed, and then runs clamscan on the given
file or directory.

`./MacClam.sh uninstall`

Uninstalls MacClam.

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

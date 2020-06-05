#!/bin/bash

pushd `dirname $0` > /dev/null
SCRIPTPATH=`pwd`/`basename $0`
popd > /dev/null

# This script is an all-in-one solution for ClamAV scanning on a Mac.
# Run this script to install it, and run it again to check for updates
# to clamav or virus definitions.  The installation does the following:
#
# 1) Downloads the latest versions of clamav and fswatch and builds
# them from source.
#
# 2) Sets the program to actively monitor the directories specified by
# $MONITOR_DIRS, and move any viruses it finds to a folder specified by
# $QUARANTINE_DIR.
#
# 3) Installs a crontab that invokes this same script once a day to
# check for virus definition updates, and once a week to perform a
# full system scan.  These scheduled times can be customized by
# editing the CRONTAB variable below.  The crontab also schedules
# MacClam to run on startup.
#
# If you pass one or more arguments to this file, all of the above
# steps are performed.  In addition, each of the arguments passed in
# will be interpreted as a file or directory to be scanned.
#
# To uninstall MacClam.sh, run `MacClam.sh uninstall'.
#
# You can customize the following variables to suit your tastes.  If
# you change them, run this script again to apply your settings.
# 

#The  top level installation directory.  It must not contain spaces or the builds won't work.
INSTALLDIR="$HOME/MacClam"

# Directories to monitor
MONITOR_DIRS=(
    "$HOME"
    "/Applications"
)

# Directory patterns to exclude from scanning (this is a substring match)
EXCLUDE_DIR_PATTERNS=(
    "/clamav-[^/]*/test/" #leave test files alone
    #"^$HOME/Library/"
    "^/mnt/"
)

# File patterns to exclude from scanning
EXCLUDE_FILE_PATTERNS=(
    '\.txt$'
)

# Pipe-separated list of filename patterns to exclude
QUARANTINE_DIR="$INSTALLDIR/quarantine"

# Log file directory
MACCLAM_LOG_DIR="$INSTALLDIR/log"
CRON_LOG="$MACCLAM_LOG_DIR/cron.log"
MONITOR_LOG="$MACCLAM_LOG_DIR/monitor.log"
CLAMD_LOG="$MACCLAM_LOG_DIR/clamd.log"

CRONTAB='
#Start everything up at reboot
@reboot '$SCRIPTPATH' >> '$CRON_LOG' 2>&1 

#Check for updates daily
@daily  '$SCRIPTPATH' >> '$CRON_LOG' 2>&1 

#Scheduled scan, every Sunday morning at 00:00.
@weekly '$SCRIPTPATH' / >> '$CRON_LOG' 2>&1 
'
# End of customizable variables

set -e

if [ "$1" == "help" -o "$1" == "-help" -o  "$1" == "--help" ]
then
    echo "Usage:

MacClam.sh               Show current scanning activity, installing clamav and fswatch if needed
MacClam.sh quarantine    Open the quarantine folder
MacClam.sh uninstall     Uninstall MacClam
MacClam.sh help          Display this message

MacClam.sh [clamdscan args] [FILE|DIRECTORY]...  

The last form launches clamdscan on specific files or directories, installing if needed.

Get more information from https://github.com/killdash9/MacClam
"
    exit
fi

if [ "$1" == "uninstall" ]
then
    read -r -p "Are you sure you want to uninstall MacClam? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
    then
        echo "Uninstalling MacClam"
        echo "Stopping services"
        sudo killall clamd fswatch || true
        echo "Uninstalling from crontab"
        crontab <(cat <(crontab -l|sed '/# BEGIN MACCLAM/,/# END MACCLAM/d;/MacClam/d'));
        if [ -d "$QUARANTINE_DIR" -a "`ls "$QUARANTINE_DIR" 2>/dev/null`" ]
        then
            echo "Moving $QUARANTINE_DIR to $HOME/MacClam_quarantine in case there's something you want in there."
            if [ -d "$HOME/MacClam_quarantine" ]
            then
                mv "$QUARANTINE_DIR/"* "$HOME/MacClam_quarantine"
            else
                mv "$QUARANTINE_DIR" "$HOME/MacClam_quarantine"
            fi
        fi
        echo "Deleting installation directory $INSTALLDIR"
        sudo rm -rf "$INSTALLDIR"
        echo "Uninstall complete.  Sorry to see you go!"
    else
        echo "Uninstall cancelled"
    fi
    exit
fi

if [ ! -t 0 ]
then
echo
echo "--------------------------------------------------"
echo " Starting MacClam.sh `date`"
echo "--------------------------------------------------"
echo
fi

chmod +x "$SCRIPTPATH"

test -d "$INSTALLDIR" || { echo "Creating installation directory $INSTALLDIR"; mkdir -p "$INSTALLDIR"; }
test -d "$MACCLAM_LOG_DIR" || { echo "Creating log directory $MACCLAM_LOG_DIR"; mkdir -p "$MACCLAM_LOG_DIR"; }
test -f "$CRON_LOG" || touch "$CRON_LOG"
test -f "$CLAMD_LOG" || touch "$CLAMD_LOG"
test -f "$MONITOR_LOG" || touch "$MONITOR_LOG"
test -d "$QUARANTINE_DIR" || { echo "Creating quarantine directory $QUARANTINE_DIR"; mkdir -p "$QUARANTINE_DIR"; }
test -f "$INSTALLDIR/clamav.ver" && CLAMAV_INS="$INSTALLDIR/clamav-installation-`cat $INSTALLDIR/clamav.ver`"

test -f "$INSTALLDIR/fswatch.ver" && FSWATCH_INS="$INSTALLDIR/fswatch-installation-`cat $INSTALLDIR/fswatch.ver`"

if [ "$1" == "quarantine" ]
then
    echo "Opening $QUARANTINE_DIR"
    open "$QUARANTINE_DIR"
    exit
fi



if [ -t 0 ] #don't do this when we're run from cron
then
    
echo
echo "-----------------------"
echo " Checking Installation"
echo "-----------------------"
echo
echo -n "What is the latest version of openssl?..."

OPENSSL_DOWNLOAD_LINK=https://www.openssl.org/source/`curl -s https://www.openssl.org/source/|grep -Eo 'openssl-1\.1\.1.{0,2}\.tar.gz'|head -1`
OPENSSL_VER="${OPENSSL_DOWNLOAD_LINK#https://www.openssl.org/source/openssl-}"
OPENSSL_VER="${OPENSSL_VER%.tar.gz}"

if [[ ! "$OPENSSL_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+[a-z]?$ ]]
then
    OPENSSL_VER='' #we didn't get a version number
fi

if [ ! "$OPENSSL_VER" ]
then
    echo "Can't lookup latest openssl version.  Looking for already-installed version."
    OPENSSL_VER=`cat $INSTALLDIR/openssl.ver`
else
    echo "$OPENSSL_VER"
    echo "$OPENSSL_VER" > "$INSTALLDIR/openssl.ver"
fi

if [ ! "$OPENSSL_VER" ]
then
    echo "No openssl installed and can't update.  Can't proceed."
    exit 1
fi

OPENSSL_TAR="$INSTALLDIR/openssl-$OPENSSL_VER.tar.gz"
OPENSSL_SRC="$INSTALLDIR/openssl-$OPENSSL_VER"
OPENSSL_INS="$INSTALLDIR/openssl-installation-$OPENSSL_VER"

echo -n "Has openssl-$OPENSSL_VER been downloaded?..."
if [ -f "$OPENSSL_TAR" ] && tar -tf "$OPENSSL_TAR" > /dev/null
then
    echo "Yes"
else
    echo "No.  Downloading $OPENSSL_DOWNLOAD_LINK to $OPENSSL_TAR"
    curl --connect-timeout 3  -L -o "$OPENSSL_TAR" "$OPENSSL_DOWNLOAD_LINK" 
fi

echo -n "Has openssl-$OPENSSL_VER been extracted?..."
if [ -d "$OPENSSL_SRC" ]
then
    echo "Yes"
else
    echo "No.  Extracting it."
    cd "$INSTALLDIR"
    tar -xf "$OPENSSL_TAR"
fi

echo -n "Has openssl-$OPENSSL_VER been built?..."
if [ -f "$OPENSSL_SRC/libcrypto.a" ]
then
    echo "Yes"
else
    echo "No.  Building it."
    cd "$OPENSSL_SRC"
    ./Configure darwin64-x86_64-cc enable-ec_nistp_64_gcc_128 no-ssl3 no-comp --openssldir="$OPENSSL_INS" --prefix="$OPENSSL_INS" &&
        make -j8
fi

echo -n "Has openssl-$OPENSSL_VER been installed?..."
if [ "$OPENSSL_INS/lib/libcrypto.a" -nt "$OPENSSL_SRC/libcrypto.a" ]
then
    echo "Yes"
else
    echo "No.  Installing it."
    cd "$OPENSSL_SRC"
    make install_sw
fi

echo -n What is the latest version of pcre?...
PCRE_VER=`curl -s --connect-timeout 15  http://www.pcre.org/|grep 'is at version '|grep -Eo '8\.[0-9]+'`
PCRE_DOWNLOAD_LINK="http://ftp.pcre.org/pub/pcre/pcre-$PCRE_VER.tar.gz"

if [[ ! "$PCRE_VER" =~ ^[0-9]+\.[0-9]+$ ]]
then
    PCRE_VER='' #we didn't get a version number
fi

if [ ! "$PCRE_VER" ]
then
    echo "Can't lookup latest pcre version.  Looking for already-installed version."
    PCRE_VER=`cat $INSTALLDIR/pcre.ver`
else
    echo "$PCRE_VER"
    echo "$PCRE_VER" > "$INSTALLDIR/pcre.ver"
fi

if [ ! "$PCRE_VER" ]
then
    echo "No pcre installed and can't update.  Can't proceed."
    exit 1
fi

PCRE_TAR="$INSTALLDIR/pcre-$PCRE_VER.tar.gz"
PCRE_SRC="$INSTALLDIR/pcre-$PCRE_VER"
PCRE_INS="$INSTALLDIR/pcre-installation-$PCRE_VER"

echo -n "Has pcre-$PCRE_VER been downloaded?..."
if [ -f "$PCRE_TAR" ] && tar -tf "$PCRE_TAR" > /dev/null
then
    echo "Yes"
else
    echo "No.  Downloading $PCRE_DOWNLOAD_LINK to $PCRE_TAR"
    curl --connect-timeout 15  -L -o "$PCRE_TAR" "$PCRE_DOWNLOAD_LINK" 
fi

echo -n "Has pcre-$PCRE_VER been extracted?..."
if [ -d "$PCRE_SRC" ]
then
    echo "Yes"
else
    echo "No.  Extracting it."
    cd "$INSTALLDIR"
    tar -xf "$PCRE_TAR"
fi

echo -n "Has pcre-$PCRE_VER been built?..."
if [ -f "$PCRE_SRC/.libs/libpcre.a" ]
then
    echo "Yes"
else
    echo "No.  Building it."
    cd "$PCRE_SRC"
    ./configure --prefix="$PCRE_INS" &&
        make -j8
fi

echo -n "Has pcre-$PCRE_VER been installed?..."
if [ "$PCRE_INS/lib/libpcre.a" -nt "$PCRE_SRC/.libs/libpcre.a" ]
then
    echo "Yes"
else
    echo "No.  Installing it."
    cd "$PCRE_SRC"
    make install
fi

echo -n "What is the latest version of clamav?..."


#ClamAV stores its version in dns
CLAMAV_VER=`dig TXT +noall +answer +time=3 +tries=1 current.cvd.clamav.net| sed 's,.*"\([^:]*\):.*,\1,'`
if [[ ! "$CLAMAV_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
then
    CLAMAV_VER='' #we didn't get a version number
fi

if [ ! "$CLAMAV_VER" ]
then
    echo "Can't lookup latest clamav version.  Looking for already-installed version."
    CLAMAV_VER=`cat $INSTALLDIR/clamav.ver`
else
    echo "$CLAMAV_VER"
    echo "$CLAMAV_VER" > "$INSTALLDIR/clamav.ver"
fi

if [ ! "$CLAMAV_VER" ]
then
    echo "No clamav installed and can't update.  Can't proceed."
    exit 1
fi

CLAMAV_TAR="$INSTALLDIR/clamav-$CLAMAV_VER.tar.gz"
CLAMAV_SRC="$INSTALLDIR/clamav-$CLAMAV_VER"
CLAMAV_INS="$INSTALLDIR/clamav-installation-$CLAMAV_VER"

#CLAMAV_DOWNLOAD_LINK=http://sourceforge.net/projects/clamav/files/clamav/$CLAMAV_VER/clamav-$CLAMAV_VER.tar.gz/download
CLAMAV_DOWNLOAD_LINK="https://www.clamav.net/downloads/production/clamav-$CLAMAV_VER.tar.gz"
#CLAMAV_DOWNLOAD_LINK="http://nbtelecom.dl.sourceforge.net/project/clamav/clamav/$CLAMAV_VER/clamav-$CLAMAV_VER.tar.gz"

echo -n "Has clamav-$CLAMAV_VER been downloaded?..."
if [ -f "$CLAMAV_TAR" ] && tar -tf "$CLAMAV_TAR" > /dev/null
then
    echo "Yes"
else
    echo "No.  Downloading $CLAMAV_DOWNLOAD_LINK to $CLAMAV_TAR"
    curl --connect-timeout 3  -L -o "$CLAMAV_TAR" "$CLAMAV_DOWNLOAD_LINK" 
fi

echo -n "Has clamav-$CLAMAV_VER been extracted?..."
if [ -d "$CLAMAV_SRC" ]
then
    echo "Yes"
else
    echo "No.  Extracting it."
    cd "$INSTALLDIR"
    tar -xf "$CLAMAV_TAR"
fi

CFLAGS="-O2 -g -D_FILE_OFFSET_BITS=64" 
CXXFLAGS="-O2 -g -D_FILE_OFFSET_BITS=64"

echo -n "Has the clamav-$CLAMAV_VER build been configured?..."
if [ -f "$CLAMAV_SRC/Makefile" ]
then
    echo "Yes"
else
    echo "No.  Configuring it."
    cd "$CLAMAV_SRC"
    ./configure --disable-dependency-tracking --enable-llvm=no --enable-clamdtop --with-user=_clamav --with-group=_clamav --enable-all-jit-targets --with-openssl="$OPENSSL_INS" --with-pcre="$PCRE_INS" --prefix="$CLAMAV_INS"
fi

echo -n "Has clamav-$CLAMAV_VER been built?..."
if [ "$CLAMAV_SRC/Makefile" -nt "$CLAMAV_SRC/clamscan/clamscan" ]
then
    echo "No.  Building it."
    cd "$CLAMAV_SRC"
    make -j8

else
    echo "Yes"

fi

echo -n "Has clamav-$CLAMAV_VER been installed?..."
if [ "$CLAMAV_SRC/clamscan/clamscan" -nt "$CLAMAV_INS/bin/clamscan" ]
then
    echo "No.  Installing it."
    cd "$CLAMAV_SRC"

    make -j8 #run make again just in case
    echo "Password needed to run \"sudo make install\" for clamav"
    sudo make install

    if [ ! "$CLAMAV_INS" ]
    then
        echo "The variable CLAMAV_INS should be set here!  Not proceeding, so we don't screw things up"
    fi

    cd "$CLAMAV_INS"
    
    sudo chown -R root:wheel ./etc
    sudo chmod 0775 ./etc
    sudo chmod 0664 ./etc/*

    sudo chown -R root:wheel ./bin
    sudo chmod -R 0755 ./bin
    sudo chown clamav ./bin/freshclam
    sudo chmod u+s ./bin/freshclam
    sudo mkdir -p ./share/clamav
    sudo chown -R clamav:clamav ./share/clamav
    sudo chmod 0775 ./share/clamav
    sudo chmod 0664 ./share/clamav/* || true

    sudo chown -R clamav:clamav ./share/clamav/daily* || true
    sudo chmod -R a+r ./share/clamav/daily* || true

    sudo chown -R clamav:clamav ./share/clamav/main* || true
    sudo chmod -R a+r ./share/clamav/main.* || true
    #sudo touch ./share/clamav/freshclam.log 
    #sudo chmod a+rw ./share/clamav/freshclam.log
    sudo chmod u+s ./sbin/clamd
else
    echo "Yes"
fi

CLAMD_CONF="$CLAMAV_INS/etc/clamd.conf"
FRESHCLAM_CONF="$CLAMAV_INS/etc/freshclam.conf"

function kill_clamd {
    sudo killall clamd
    echo Giving it time to stop...
    sleep 3;
    if pgrep clamd
    then
        echo "It's still running, using kill -9"
        sudo killall -9 clamd
        echo "Waiting one second"
        sleep 1;
    fi
}
echo -n "Is clamd.conf up to date?..."
TMPFILE=`mktemp -dt "MacClam"`/clamd.conf
sed "
/^Example/d
\$a\\
LogFile $CLAMD_LOG\\
LogTime yes\\
MaxDirectoryRecursion 30\\
LocalSocket /tmp/clamd.socket\\
" "$CLAMD_CONF.sample" > "$TMPFILE"

for p in "${EXCLUDE_DIR_PATTERNS[@]}"
do
    echo ExcludePath $p >> "$TMPFILE"
done

if cmp -s "$TMPFILE" "$CLAMD_CONF" 
then
    echo Yes
else
    echo "No.  Updating $CLAMD_CONF"
    sudo cp "$TMPFILE" "$CLAMD_CONF"
    echo "Killing clamd if it's running"
    kill_clamd
fi
rm "$TMPFILE"

echo -n "Is freshclam.conf up to date?..."
TMPFILE=`mktemp -dt "MacClam"`/freshclam.conf
sed "
/^Example/d
\$a\\
NotifyClamd $CLAMD_CONF\\
MaxAttempts 1\\
" "$FRESHCLAM_CONF.sample" > "$TMPFILE"
if cmp -s "$TMPFILE" "$FRESHCLAM_CONF" 
then
    echo Yes
else
    echo "No. Updating $FRESHCLAM_CONF"
    sudo cp "$TMPFILE" "$FRESHCLAM_CONF"
fi
rm "$TMPFILE"

echo -n "What is the latest version of fswatch?..."
FSWATCH_DOWNLOAD_LINK=https://github.com`curl -L -s 'https://github.com/emcrisostomo/fswatch/releases/latest'| grep "/emcrisostomo/fswatch/releases/download/.*tar.gz"|sed 's,.*href *= *"\([^"]*\).*,\1,'`
FSWATCH_VER="${FSWATCH_DOWNLOAD_LINK#https://github.com/emcrisostomo/fswatch/releases/download/}"
FSWATCH_VER="${FSWATCH_VER%/fswatch*}"

if [[ ! "$FSWATCH_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
then
    FSWATCH_VER='' #we didn't get a version number
fi

if [ ! "$FSWATCH_VER" ]
then
    echo "Can't lookup latest fswatch version.  Looking for already-installed version."
    FSWATCH_VER=`cat $INSTALLDIR/fswatch.ver`
else
    echo "$FSWATCH_VER"
    echo "$FSWATCH_VER" > "$INSTALLDIR/fswatch.ver"
fi

if [ ! "$FSWATCH_VER" ]
then
    echo "No fswatch installed and can't update.  Can't proceed."
    exit 1
fi

FSWATCH_TAR="$INSTALLDIR/fswatch-$FSWATCH_VER.tar.gz"
FSWATCH_SRC="$INSTALLDIR/fswatch-$FSWATCH_VER"
FSWATCH_INS="$INSTALLDIR/fswatch-installation-$FSWATCH_VER"

echo -n "Has the latest fswatch been downloaded?..."
if [ -f "$FSWATCH_TAR" ] && tar -tf "$FSWATCH_TAR" > /dev/null
then
    echo "Yes"
else
    echo "No.  Downloading $FSWATCH_DOWNLOAD_LINK"
    curl -L -o "$FSWATCH_TAR" "$FSWATCH_DOWNLOAD_LINK" 
fi

echo -n "Has fswatch been extracted?..."
if [ -d "$FSWATCH_SRC" ]
then
    echo "Yes"
else
    echo "No.  Extracting it."
    cd "$INSTALLDIR"
    tar -xf "$FSWATCH_TAR"
fi

echo -n "Has fswatch been configured?..."
if [ -f "$FSWATCH_SRC/Makefile" ]
then
    echo "Yes"
else
    echo "No.  Configuring it."
    cd "$FSWATCH_SRC"
    ./configure --prefix="$FSWATCH_INS"
fi

echo -n "Has fswatch been installed?..."
if [ -d $FSWATCH_INS ]
then
    echo "Yes"
else
    echo "No.  Building and installing it."
    cd "$FSWATCH_SRC"

    make -j8
    echo "Password needed to run sudo make install"
    sudo make install
    sudo chown root:wheel "$FSWATCH_INS/bin/fswatch"
    sudo chmod u+s "$FSWATCH_INS/bin/fswatch"

fi

echo Creating scaniffile
cat > "$INSTALLDIR/scaniffile" <<EOF
#!/bin/bash
#this is invoked on files detected by fswatch.  It scans if its argument is a file
if [ -f "\$1" ]
then
  output=\`"$CLAMAV_INS/bin/clamdscan" -v --config-file="$CLAMD_CONF" --move="$QUARANTINE_DIR" --no-summary "\$1"\`
  if [ \$? == 1 ]
  then
      echo \`date\` \$output >> "$QUARANTINE_DIR/quarantine.log"
      osascript -e "display notification \"\$output\" with title \"MacClam\" subtitle \"\$1\"" &
  fi
  echo \$output
fi
EOF
chmod +x "$INSTALLDIR/scaniffile"

fi #end if [ -t 0 ] 

CLAMD_CONF="$CLAMAV_INS/etc/clamd.conf"
FRESHCLAM_CONF="$CLAMAV_INS/etc/freshclam.conf"

echo -n Is crontab up to date?...
CURRENT_CRONTAB=`crontab -l |awk '/# BEGIN MACCLAM/,/# END MACCLAM/'`
EXPECTED_CRONTAB="# BEGIN MACCLAM
$CRONTAB
# END MACCLAM"
if [ "$CURRENT_CRONTAB" == "$EXPECTED_CRONTAB" ]
then
    echo Yes
else
    if [ -t 0 ]
    then
        echo No.  Updating it.
        crontab <(cat <(crontab -l|sed '/# BEGIN MACCLAM/,/# END MACCLAM/d;/MacClam/d'); echo "$EXPECTED_CRONTAB")
    else
        echo No.  Run $0 from the command line to update it.
    fi
fi

echo
echo "---------------------------------------"
echo " Checking for ClamAV Signature Updates "
echo "---------------------------------------"
echo

if [ -t 0 ]
then
    "$CLAMAV_INS/bin/freshclam" --config-file="$FRESHCLAM_CONF" || true
else
    "$CLAMAV_INS/bin/freshclam "--quiet --config-file="$FRESHCLAM_CONF" || true
fi

echo
echo "-----------------------------"
echo " Ensure Services are Running"
echo "-----------------------------"
echo
echo -n Is clamd runnning?...

CLAMD_CMD_ARGS=(
    "$CLAMAV_INS/sbin/clamd"
    "--config-file=$CLAMD_CONF"
)
CLAMD_CMD="$(printf " %q" "${CLAMD_CMD_ARGS[@]}")"

#CLAMD_CMD='$CLAMAV_INS/sbin/clamd --config-file=$CLAMD_CONF'
if PID=`pgrep clamd`
then
    echo Yes
    echo -n Is it the current version?...
    if [ "`ps -o command= $PID`" == "`eval echo $CLAMD_CMD`" ]
    then
        echo Yes
    else
        if [ -t 0 ]
        then
            echo No.  Killing it.
            kill_clamd
            echo "Starting clamd"
            eval $CLAMD_CMD
        else
            No.  Run $0 from the command line to update it.
        fi
    fi
else
    echo No.  Starting it.
    eval $CLAMD_CMD
fi

echo -n Is fswatch running?...
FSWATCH_CMD_ARGS=(
    "$FSWATCH_INS/bin/fswatch"
    -E
    -e "$QUARANTINE_DIR"
    "${EXCLUDE_DIR_PATTERNS[@]/#/-e}"
    "${EXCLUDE_FILE_PATTERNS[@]/#/-e}"
    -e "$MONITOR_LOG"
    -e "$CLAMD_LOG"
    -e "$CRON_LOG"
    "${MONITOR_DIRS[@]}"
)

#FSWATCH_CMD='"'$FSWATCH_INS'/bin/fswatch" -E -e "'$QUARANTINE_DIR'" "'${EXCLUDE_DIR_PATTERNS[@]/#/-e}'" "'${EXCLUDE_FILE_PATTERNS[@]/#/-e}'" -e "'$MONITOR_LOG'" -e "'$CLAMD_LOG'" -e "'$CRON_LOG'" "'${MONITOR_DIRS[@]}'"'

FSWATCH_CMD="$(printf " %q" "${FSWATCH_CMD_ARGS[@]}")"

function runfswatch {
    cat > "$INSTALLDIR/runfswatch" <<EOF 
#!/bin/bash
#Launches fswatch and sends its output to scaniffile
$FSWATCH_CMD | while read line; do "$INSTALLDIR/scaniffile" "\$line"; done >> "$MONITOR_LOG" 2>&1
EOF

    chmod +x "$INSTALLDIR/runfswatch"
    script -q /dev/null "$INSTALLDIR/runfswatch"
}

if PID=`pgrep fswatch`
then
    echo Yes

    echo -n Is it running the latest version and configuration?...
    if [ "`ps -o command= $PID`" == "`eval echo $FSWATCH_CMD`" ]
    then
        echo Yes
    else
        if [ -t 0 ]
        then
            echo No.  Restarting.
            sudo killall fswatch
            runfswatch &
        else
            echo No.  Run $0 from the command line to update it.
        fi
    fi
else
    echo No.  Starting it.
    runfswatch &
fi

echo
echo Monitoring ${MONITOR_DIRS[@]}
echo
if [ "$1" ]
then
    set -x
    "$CLAMAV_INS/bin/clamdscan" --move="$QUARANTINE_DIR" "$@"
    exit
elif [ -t 0 ]
then
    echo
    echo "------------------"
    echo " Current Activity "
    echo "------------------"
    echo
    echo "You can press Control-C to stop viewing activity.  Scanning services will continue running."
    echo
    {
        tput colors > /dev/null && 
            green="$(tput setaf 2)" &&
            red="$(tput setaf 1)" &&
            yellow="$(tput setaf 3)" && 
            cyan="$(tput setaf 6)" && 
            normal="$(tput sgr0)"
    } || true
    
    (tail -0F "$CLAMD_LOG" "$CRON_LOG" "$MONITOR_LOG" | awk '
BEGIN {
    tmax=max(30,'"`tput cols`"')
    e="\033["
    viruscnt='"`ls $QUARANTINE_DIR|wc -l`"'
    r="'"$red"'"
    g="'"$green"'"
    y="'"$yellow"'"
    c="'"$cyan"'"
    n="'"$normal"'"
}

/^\/.* FOUND/ {
    sub(/ FOUND$/,r" FOUND"n)
    cnt++
    viruscnt++
}
/^\/.* (Empty file|OK)/ {
    cnt++
    l=length
    filename()
    countstr=sprintf("%d scanned ",cnt)
    virusstr=viruscnt? virusstr=sprintf("%d vir ",viruscnt):""
    printf e"K" y countstr r virusstr n
    tmax_ = tmax-length(countstr)-length(virusstr)
    dmax=max(tmax_-30,tmax_/2);
    if (l<tmax_) {
        sub(/OK$/,g"OK"n)
        printf "%s\r",$0
    }
    else {
        match($0,"/[^/]*$")
        dir=substr($0,1,min(l-RLENGTH,dmax))
        file=substr($0,l-min(tmax_-length(dir),RLENGTH)+1)
        dir=substr(dir,1,length(dir)-3)
        sub(/OK$/,g"OK"n,file)
        printf "%s...%s\r",dir,file
    }
    fflush;next
}
/SelfCheck: Database status OK./ {
    filename()
    printf e"K%."tmax"s\r",$0
    fflush;next
}
/^==> / {
    if (pf) {
        printf c e"A"e"K%."tmax"s\r"e"B" n,$0
    }
    else {
        printf c "%."tmax"s\n" n,f=$0
        pf=1
    }
    fflush;next
}
!/^ *$/ {
    sub(/ERROR/,r"ERROR"n)
    sub(/WARNING/,y"WARNING"n)
    print e"K"$0
    pf=0
}
function filename(){
    if (!pf) {
        printf "'"$cyan"'" "%." tmax"s\n" "'"$normal"'",f
        pf=1
    }
}
function min(a,b){return a<b?a:b}
function max(a,b){return a>b?a:b}
') ||  {
        echo
        echo
        echo "Stopped showing activity.  Scan services continue to run."
        echo "Run the script again at any time to view activity."
        echo "Run 'MacClam.sh help' for more commands."
    }
fi

if [ ! -t 0 ]
then
echo
echo "--------------------------------------------------"
echo " Finished MacClam.sh `date`"
echo "--------------------------------------------------"
echo
fi

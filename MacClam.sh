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
# $FSWATCHDIRS, and move any viruses it finds to a folder specified by
# $QUARANTINE_DIR.
#
# 3) Installs a crontab that invokes this same script once a day to
# check for virus definition updates, and once a week to perform a
# full system scan.  These scheduled times can be customized by
# editing the CRONTAB variable below.  The crontab also sechedules
# MacClam to run on startup.
#
# If you pass one or more arguments to this file, all of the above
# steps are performed.  In addition, each of the arguments passed in
# will be interpreted as a file or directory to be scanned.
#
# To uninstall MacClam.sh, run `MacClam.sh uninstall'.
#
# You can customize the following variables to suite your tastes.  If
# you change them, run this script again to apply your settings.
# 


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
    #'\.jpg$'
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

if [ "$1" == "uninstall" ]
then
    read -r -p "Are you sure you want to install MacClam? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
    then
        echo "Uninstalling MacClam"
        echo "Stopping services"
        sudo killall clamd fswatdh || true
        echo "Uninstalling from crontab"
        crontab <(cat <(crontab -l|sed '/# BEGIN MACCLAM/,/# END MACCLAM/d;/MacClam/d'));
        if [ -d "$QUARANTINE_DIR" ]
        then
            echo "Moving $QUARANTINE_DIR to $HOME/MacClam_quarantine in case there's something you want in there."
            if [ -d "$HOME/MacClam_quarantine" ]
            then
                mv "$QUARANTINE_DIR/*" "$HOME/MacClam_quarantine"
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

if [ "$1" == "quarantine" ]
then
    echo "Opening $QUARANTINE_DIR"
    open "$QUARANTINE_DIR"
    exit
fi

echo
echo "--------------------------------------------------"
echo " Starting MacClam.sh `date`"
echo "--------------------------------------------------"
echo

chmod +x "$SCRIPTPATH"

test -d "$INSTALLDIR" || { echo "Creating installation directory $INSTALLDIR"; mkdir -p "$INSTALLDIR"; }
test -d "$MACCLAM_LOG_DIR" || { echo "Creating log directory $MACCLAM_LOG_DIR"; mkdir -p "$MACCLAM_LOG_DIR"; }
test -f "$CRON_LOG" || touch "$CRON_LOG"
test -f "$CLAMD_LOG" || touch "$CLAMD_LOG"
test -f "$MONITOR_LOG" || touch "$MONITOR_LOG"
test -d "$QUARANTINE_DIR" || { echo "Creating quarantine directory $QUARANTINE_DIR"; mkdir -p "$QUARANTINE_DIR"; }
test -f "$INSTALLDIR/clamav.ver" && CLAMAV_INS="$INSTALLDIR/clamav-installation-`cat $INSTALLDIR/clamav.ver`"

test -f "$INSTALLDIR/fswatch.ver" && FSWATCH_INS="$INSTALLDIR/fswatch-installation-`cat $INSTALLDIR/fswatch.ver`"

if [ -t 0 ] #don't do this when we're run from cron
then
    
echo
echo "--------------------"
echo " Verifying software"
echo "--------------------"
echo
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
CLAMAV_DOWNLOAD_LINK="http://nbtelecom.dl.sourceforge.net/project/clamav/clamav/$CLAMAV_VER/clamav-$CLAMAV_VER.tar.gz"

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
    ./configure --disable-dependency-tracking --enable-llvm=no --enable-clamdtop --with-user=_clamav --with-group=_clamav --enable-all-jit-targets --prefix="$CLAMAV_INS"
fi

echo -n "Has clamav-$CLAMAV_VER been built?..."
if [ "$CLAMAV_SRC/Makefile" -nt "$CLAMAV_SRC/clamscan/clamscan" ]
then
    echo "No.  Building it."
    cd "$CLAMAV_SRC"

    echo Patching it

    # This bit of code modifies how quarantined files are named.  The
    # name includes the original location of the file, the name of the
    # virus found in the file and the timestamp when it was
    # quarantined.  This allows you to put it back in its original
    # location if it shouldn't have been quarantined.
    
    patch -p1 <<'EOF'
diff -u a/clamdscan/proto.c b/clamdscan/proto.c
--- a/clamdscan/proto.c	2015-04-22 13:49:57.000000000 -0600
+++ b/clamdscan/proto.c	2015-07-20 21:44:56.000000000 -0600
@@ -323,12 +323,12 @@
 		if(filename) {
 		    if(scantype >= STREAM) {
 			logg("~%s%s FOUND\n", filename, colon);
-			if(action) action(filename);
+			if(action) action(filename,*(colon+1) && *(colon+2)? colon+2:NULL);
 		    } else {
 			logg("~%s FOUND\n", bol);
 			*colon = '\0';
 			if(action)
-			    action(bol);
+               action(bol,*(colon+1) && *(colon+2)? colon+2:NULL);
 		    }
 		}
 	    } else if(!memcmp(eol-7, " ERROR", 6)) {
@@ -511,7 +511,7 @@
 		c->infected++;
 		c->printok = 0;
 		logg("~%s%s\n", filename, colon);
-		if(action) action(filename);
+		if(action) action(filename,*(colon+1) && *(colon+2)? colon+2:NULL);
 	    } else if(!memcmp(eol-7, " ERROR", 6)) {
 		c->errors++;
 		c->printok = 0;
diff -u a/clamscan/manager.c b/clamscan/manager.c
--- a/clamscan/manager.c	2015-04-22 13:49:58.000000000 -0600
+++ b/clamscan/manager.c	2015-07-20 21:16:04.000000000 -0600
@@ -398,7 +398,7 @@
     close(fd);
 
     if(ret == CL_VIRUS && action)
-        action(filename);
+        action(filename,virname);
 }
 
 static void scandirs(const char *dirname, struct cl_engine *engine, const struct optstruct *opts, unsigned int options, unsigned int depth, dev_t dev)
diff -u a/shared/actions.c b/shared/actions.c
--- a/shared/actions.c	2015-04-22 13:50:12.000000000 -0600
+++ b/shared/actions.c	2015-07-20 21:57:01.000000000 -0600
@@ -39,7 +39,7 @@
 #include "shared/misc.h"
 #include "shared/actions.h"
 
-void (*action)(const char *) = NULL;
+void (*action)(const char *, const char*) = NULL;
 unsigned int notmoved = 0, notremoved = 0;
 
 static char *actarget;
@@ -47,7 +47,7 @@
 
 
 
-static int getdest(const char *fullpath, char **newname) {
+static int getdest(const char *fullpath, char* virname, char **newname) {
     char *tmps, *filename;
     int fd, i;
 
@@ -58,11 +58,22 @@
     }
     filename = basename(tmps);
 
-    if(!(*newname = (char *)malloc(targlen + strlen(filename) + 6))) {
+    if (!virname) virname="";
+    char curtime[sizeof "2011-10-08 070709"];
+    if(!(*newname = (char *)malloc(targlen + strlen(tmps) + 1 + sizeof(curtime) + 1 + sizeof(virname) + 6))) {
 	free(tmps);
 	return -1;
     }
-    sprintf(*newname, "%s"PATHSEP"%s", actarget, filename);
+    time_t now;
+    time(&now);
+    strftime(curtime, sizeof curtime, "%F %H%M%S", localtime(&now));
+    sprintf(*newname, "%s"PATHSEP"%s %s %s", actarget, fullpath, virname, curtime);
+    // replace path separators
+    for(char* c=*newname + strlen(actarget) + 1;*c;c++) {
+      if (*c == '/') {
+        *c=':';
+      }
+    }
     for(i=1; i<1000; i++) {
 	fd = open(*newname, O_WRONLY | O_CREAT | O_EXCL, 0600);
 	if(fd >= 0) {
@@ -78,9 +89,9 @@
     return -1;
 }
 
-static void action_move(const char *filename) {
+static void action_move(const char *filename, const char* virname) {
     char *nuname;
-    int fd = getdest(filename, &nuname), copied = 0;
+    int fd = getdest(filename, virname, &nuname), copied = 0;
 
     if(fd<0 || (rename(filename, nuname) && (copied=1) && filecopy(filename, nuname))) {
 	logg("!Can't move file %s\n", filename);
@@ -97,9 +108,9 @@
     if(nuname) free(nuname);
 }
 
-static void action_copy(const char *filename) {
+static void action_copy(const char *filename, const char* virname) {
     char *nuname;
-    int fd = getdest(filename, &nuname);
+    int fd = getdest(filename, virname, &nuname);
 
     if(fd < 0 || filecopy(filename, nuname)) {
 	logg("!Can't copy file '%s'\n", filename);
@@ -112,7 +123,7 @@
     if(nuname) free(nuname);
 }
 
-static void action_remove(const char *filename) {
+static void action_remove(const char *filename, const char* virname) {
     if(unlink(filename)) {
 	logg("!Can't remove file '%s'.\n", filename);
 	notremoved++;
diff -u a/shared/actions.h b/shared/actions.h
--- a/shared/actions.h	2015-04-22 13:50:12.000000000 -0600
+++ b/shared/actions.h	2015-07-20 21:09:49.000000000 -0600
@@ -23,7 +23,7 @@
 
 #include "shared/optparser.h"
 
-extern void (*action)(const char *);
+extern void (*action)(const char *, const char *);
 int actsetup(const struct optstruct *opts);
 extern unsigned int notremoved, notmoved;
 
EOF
    make

else
    echo "Yes"

fi

echo -n "Has clamav-$CLAMAV_VER been installed?..."
if [ "$CLAMAV_SRC/clamscan/clamscan" -nt "$CLAMAV_INS/bin/clamscan" ]
then
    echo "No.  Installing it."
    cd "$CLAMAV_SRC"

    make #run make again just in case
    echo "Password needed to run sudo make install"
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

echo -n "Is clamd.conf up to date?..."
TMPFILE=`mktemp -dt "MacClam"`/clamd.conf
sed "
/^Example/d
\$a\\
LogFile $CLAMD_LOG\\
LocalSocket /tmp/clamd.socket\\
" "$CLAMD_CONF.sample" > "$TMPFILE"
if cmp -s "$TMPFILE" "$CLAMD_CONF" 
then
    echo Yes
else
    echo "No.  Updating $CLAMD_CONF"
    sudo cp "$TMPFILE" "$CLAMD_CONF"
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

    make
    echo "Password needed to run sudo make install"
    sudo make install
    sudo chown root:wheel "$FSWATCH_INS/bin/fswatch"
    sudo chmod u+s "$FSWATCH_INS/bin/fswatch"

fi

echo Creating scaniffile
#if [ -f \"\$1\" ]
#then
#output=\`$CLAMAV_INS/bin/clamdscan --config-file=$CLAMD_CONF --move=$INSTALLDIR/quarantine \"\$1\"\`
#case \$? in 
#1) osascript -e \"display notification \\\"\$output\\\" with title \\\"ClamAV\\\"\";;
#2) osascript -e \"display notification \\\"Active monitor exiting because clamd is not running\\\" with title \\\"ClamAV\\\"\";;
#test \$? == \"1\" && 
#fi

echo "#!/bin/bash
#this is invoked by fswatch.  It scans if its argument is a file
if [ -f \"\$1\" ]
then
  output=\`\"$CLAMAV_INS/bin/clamdscan\" -v --config-file=\"$CLAMD_CONF\" --move=\"$QUARANTINE_DIR\" --no-summary \"\$1\"\`
  #test \$? == \"1\" && osascript -e \"display notification \\\"\$output\\\" with title \\\"ClamAV\\\"\"
  echo \"\$output\"
fi
" > "$INSTALLDIR/scaniffile"
chmod +x "$INSTALLDIR/scaniffile"

fi #end if [ -t 0 ] 

CLAMD_CONF="$CLAMAV_INS/etc/clamd.conf"
FRESHCLAM_CONF="$CLAMAV_INS/etc/freshclam.conf"

echo "Updating crontab"
crontab <(cat <(crontab -l|sed '/# BEGIN MACCLAM/,/# END MACCLAM/d;/MacClam/d'); echo "# BEGIN MACCLAM
$CRONTAB
# END MACCLAM")

echo
echo "----------------------------"
echo " Updating ClamAV Signatures"
echo "----------------------------"
echo
$CLAMAV_INS/bin/freshclam --config-file="$FRESHCLAM_CONF" || true

echo
echo "------------------"
echo " Running Software"
echo "------------------"
echo
echo -n Is clamd runnning?...

CLAMD_CMD='$CLAMAV_INS/sbin/clamd --config-file=$CLAMD_CONF'
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
FSWATCH_CMD='"$FSWATCH_INS/bin/fswatch" -E -e "$QUARANTINE_DIR" "${EXCLUDE_DIR_PATTERNS[@]/#/-e}" "${EXCLUDE_FILE_PATTERNS[@]/#/-e}" -e "$MONITOR_LOG" -e "$CLAMD_LOG" -e "$CRON_LOG" "${MONITOR_DIRS[@]}"'
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
            eval "$FSWATCH_CMD" | while read line; do "$INSTALLDIR/scaniffile" "$line"; done >> "$MONITOR_LOG" 2>&1 & disown
        else
            echo No.  Run $0 from the command line to update it.
        fi
    fi
else
    echo No.  Starting it.
    eval "$FSWATCH_CMD" | while read line; do "$INSTALLDIR/scaniffile" "$line"; done >> "$MONITOR_LOG" 2>&1 & disown
fi

echo Monitoring ${MONITOR_DIRS[@]}

if [ "$1" ]
then
    if ! [ -t 0 ] && pgrep clamscan
    then
        echo "It's time to scan $1, but a previous clamscan is still running.  Not starting another one"
    else
        echo "Scanning $@"
        "$CLAMAV_INS/bin/clamscan" -r --exclude-dir="$QUARANTINE_DIR" "${EXCLUDE_DIR_PATTERNS[@]/#/--exclude-dir=}" "${EXCLUDE_FILE_PATTERNS[@]/#/--exclude=}" --move="$QUARANTINE_DIR" "$@"
    fi
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
    }
fi

echo
echo "--------------------------------------------------"
echo " Finished MacClam.sh `date`"
echo "--------------------------------------------------"
echo

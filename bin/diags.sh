#!/bin/sh
#
##############################################################################
#

# change to directory of this script
cd "$(dirname "$0")"

# load configuration
if [ -e "config.sh" ]; then
	source ./config.sh
else
	TMPFILE=/tmp/tmp.onlinescreensaver.png
fi

# load utils
if [ -e "utils.sh" ]; then
	source ./utils.sh
else
	echo "Could not find utils.sh in `pwd`"
	exit
fi

BATT=`powerd_test -s | awk -F: '/Battery Level/ {print $2}' | sed 's/[ %]//g'`

if [ 1 -eq $DO_QUERYSTRING ]; then
        URI=$IMAGE_URI"?KindleBatt=$BATT"
else
	URI=$IMAGE_URI
fi
        
DUMP=/mnt/us/extensions/onlinescreensaver/diags/
mkdir $DUMP
lipc-get-prop com.lab126.cmd wirelessEnable >$DUMP"wireless"
powerd_test -s >$DUMP"powerd_test"
echo $URI >$DUMP"uri"
ps -ef >$DUMP"ps"
dmesg >$DUMP"dmesg"
ifconfig >$DUMP"ifconfig" 2>&1
ping -c 192.168.70.1 >$DUMP"ping" 2>&1

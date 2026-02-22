#!/bin/sh
#
##############################################################################
#
# Fetch weather screensaver from a configurable URL.

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

# do nothing if no URL is set
if [ -z $IMAGE_URI ]; then
	logger "No image URL has been set. Please edit config.sh."
	return
fi

logger "update called"

# enable wireless if it is currently off
if [ 0 -eq `lipc-get-prop com.lab126.cmd wirelessEnable` ]; then
	logger "WiFi is off, turning it on now"
	lipc-set-prop com.lab126.cmd wirelessEnable 1
fi

# wait for network to be up
TIMER=${NETWORK_TIMEOUT}     # number of seconds to attempt a connection
CONNECTED=0                  # whether we are currently connected
while [ 0 -eq $CONNECTED ]; do
	# test whether we can ping outside
	logger "pinging ..."
	/bin/ping -c 1 $TEST_DOMAIN > /dev/null && CONNECTED=1

	# if we can't, checkout timeout or sleep for 1s
	if [ 0 -eq $CONNECTED ]; then
		TIMER=$(($TIMER-1))
		if [ 0 -eq $TIMER ]; then
			logger "No internet connection after ${NETWORK_TIMEOUT} seconds, aborting."
			break
		fi
	fi
	sleep 10
	logger "Wait for Internet loop: ${TIMER} remaining, CONNECTED = ${CONNECTED}"
done

#logger "update after waiting for connection"
                                              
BATT=`powerd_test -s | awk -F: '/Battery Level/ {print $2}' | sed 's/[ %]//g'`
REMAIN=`/usr/bin/powerd_test -s | awk -F: '/Remaining time in this state: / {print $2}' | sed 's/\.[0-9]*//g' | sed 's/ //g'`
CHARGING=$(/usr/bin/powerd_test -s 2>/dev/null | awk -F: '/Charging/ {gsub(/^ +| +$/,"",$2); print $2}')

if [ 1 -eq $DO_QUERYSTRING ]; then
        URI=$IMAGE_URI"?batteryLevel=$BATT&isCharging=${IS_CHARGING}&remainInState=$REMAIN"
else
	URI=$IMAGE_URI
fi
        
if [ 1 -eq $CONNECTED ]; then
	logger "wget $URI"
	logger "Tempfile is $TMPFILE"
	
	rm $TMPFILE 2>/dev/null
	sh -c "sleep 10; /mnt/us/extensions/onlinescreensaver/bin/killget.sh" &
	if wget -q $URI -O $TMPFILE; then
		mv $TMPFILE $SCREENSAVERFILE
		logger "Screen saver image file updated"
		# refresh screen
		lipc-get-prop com.lab126.powerd status | grep "Screen Saver" && (
				logger "Updating image on screen"
				eips -f -g $SCREENSAVERFILE
				if [ 1 -eq $BATTDISP ]; then
				eips 40 1 "Batt:$BATT"
				fi
		)
	else
		logger "Error updating screensaver (wget)"
		if [ 1 -eq $DONOTRETRY ]; then
			touch $SCREENSAVERFILE
		fi
	fi

	logger "wget $CONF_URI"
	rm $TMPCFILE 2>/dev/null
	if wget -q $CONF_URI -O $TMPCFILE; then
		if grep EXTRASLEEP $TMPCFILE; then
			logger "config file downloaded"
			mv $TMPCFILE $CONFIGFILE
		else 
			logger "config file not downloaded"
		fi
	fi	
fi

if [ $EXTRASLEEP -gt "0" ]; then
	# needed to allow time to sync and such things in case wlan is strong and wake cycle is very short
	logger "Extra sleep: $EXTRASLEEP seconds"
	sleep $EXTRASLEEP;
fi



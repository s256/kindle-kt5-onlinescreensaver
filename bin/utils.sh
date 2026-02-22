##############################################################################
# Logs a message to a log file (or to console if argument is /dev/stdout)

logger () {
	MSG=$1
	
	# do nothing if logging is not enabled
	if [ "x1" != "x$LOGGING" ]; then
		return
	fi

	# if no logfile is specified, set a default
	if [ -z $LOGFILE ]; then
		$LOGFILE=stdout
	fi

    if [ -n "$REMOTE_LOG" ]; then
        # Send as syslog-formatted UDP datagram (facility=local0, severity=info)
        RHOST="${REMOTE_LOG%%:*}"
        RPORT="${REMOTE_LOG##*:}"
        echo "<134>kindle-dashboard: $MSG" | nc "$RHOST" "$RPORT" 2>/dev/null &
    fi

	echo `date`: $MSG >> $LOGFILE
}


##############################################################################
# Retrieves the current time in seconds

currentTime () {
	date +%s
}


##############################################################################
# sets an RTC alarm
# arguments: $1 - time in seconds from now

wait_for () { 
	delay=$1
	now=$(currentTime)
	BATT=`/usr/bin/powerd_test -s | awk -F: '/Battery Level/ {print $2}' | sed 's/[ %]//g'`
	STATE=`/usr/bin/powerd_test -s | awk -F: '/Powerd state: / {print $2}' | sed 's/ //g'`
	REMAIN=`/usr/bin/powerd_test -s | awk -F: '/Remaining time in this state: / {print $2}' | sed 's/\.[0-9]*//g' | sed 's/ //g'`

    if [ "x1" == "x$LOGGING" ]; then
		logger "wait_for called with $delay, now=$now, State: $STATE, Remaining time in this state: $REMAIN, Batt: $BATT"
	fi		
	# calculate the time we should return
	ENDWAIT=$(( $(currentTime) + $1 ))

	# wait for timeout to expire
	while [ $(currentTime) -lt $ENDWAIT ]; do
		REMAININGWAITTIME=$(( $ENDWAIT - $(currentTime) ))
		STATE=`/usr/bin/powerd_test -s | awk -F: '/Powerd state: / {print $2}' | sed 's/ //g'`
		REMAIN=`/usr/bin/powerd_test -s | awk -F: '/Remaining time in this state: / {print $2}' | sed 's/\.[0-9]*//g' | sed 's/ //g'`
		if [ 0 -lt $REMAININGWAITTIME ]; then
			if [ "x$STATE" == "xScreenSaver" ]
			then
				# in screensaver mode
				logger "screensaver mode"
				# is kindle about to fall into sleep?
				if [ "$REMAIN" -lt "43200" ]; then
					logger "Remaining time in screensaver state is less than 12 hours - simulate button press"
					/usr/bin/powerd_test -p
					STATE=`/usr/bin/powerd_test -s | awk -F: '/Powerd state: / {print $2}' | sed 's/ //g'`
					logger "now in state $STATE"
					sleep 1
					logger "another button press ..."
					/usr/bin/powerd_test -p
					sleep 1
					STATE=`/usr/bin/powerd_test -s | awk -F: '/Powerd state: / {print $2}' | sed 's/ //g'`
					logger "now in state $STATE"
				fi
				if [ "$BATT" -lt "5" ]; then
					logger "Batt less than 5%, prevent RTC sleep"
					sleep $REMAININGWAITTIME
					return
				fi
					
				logger "go to RTC sleep for $REMAININGWAITTIME seconds"
				sleep 3
				/mnt/us/extensions/onlinescreensaver/bin/rtcwake -d rtc$RTC -s $REMAININGWAITTIME -m mem
				logger "woke up again"
				sleep 3
				return
			else
				# not in screensaver mode - don't really sleep with rtcwake
				logger "not in screensaver mode but in state $STATE"
				sleep 10
			fi
		fi
	done
}


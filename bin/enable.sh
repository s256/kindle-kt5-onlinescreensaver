#!/bin/sh

# change to directory of this script
cd "$(dirname "$0")"

# load configuration
if [ -e "config.sh" ]; then
	source ./config.sh
fi

# load utils
if [ -e "utils.sh" ]; then
	source ./utils.sh
else
	echo "Could not find utils.sh in `pwd`"
	exit
fi


if [ -e /etc/upstart ]; then
	logger "Enabling online screensaver auto-update"

	mntroot rw
	cp onlinescreensaver.conf /etc/upstart/
	mntroot ro

	start onlinescreensaver
else
	mntroot rw
	cp /mnt/us/extensions/onlinescreensaver/bin/startup-file /etc/init.d/onlinescreensaver
	ln -s /etc/init.d/onlinescreensaver /etc/rc0.d/K08onlinescreensaver
	ln -s /etc/init.d/onlinescreensaver /etc/rc1.d/K08onlinescreensaver
	ln -s /etc/init.d/onlinescreensaver /etc/rc2.d/K08onlinescreensaver
	ln -s /etc/init.d/onlinescreensaver /etc/rc3.d/K08onlinescreensaver
	ln -s /etc/init.d/onlinescreensaver /etc/rc4.d/K08onlinescreensaver
	ln -s /etc/init.d/onlinescreensaver /etc/rc5.d/S99onlinescreensaver
	ln -s /etc/init.d/onlinescreensaver /etc/rc6.d/K08onlinescreensaver
	cp t1_timeout /etc/kdb.src/yoshi/system/daemon/powerd/
	cp t2_timeout /etc/kdb.src/yoshi/system/daemon/powerd/
	/etc/init.d/powerd restart
	mntroot ro
	logger "enabled."
	/etc/init.d/onlinescreensaver start
fi

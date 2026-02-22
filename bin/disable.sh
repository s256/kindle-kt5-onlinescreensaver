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

# forever and ever, try to update the screensaver
logger "Disabling online screensaver auto-update"

mntroot rw
if [ -e /etc/upstart ]; then
	echo "removing upstart file"
	stop onlinescreensaver || true      
	rm /etc/upstart/onlinescreensaver.conf
else
	/etc/init.d/onlinescreensaver stop
	rm /etc/init.d/onlinescreensaver
	rm /etc/rc0.d/K08onlinescreensaver
	rm /etc/rc1.d/K08onlinescreensaver
	rm /etc/rc2.d/K08onlinescreensaver
	rm /etc/rc3.d/K08onlinescreensaver
	rm /etc/rc4.d/K08onlinescreensaver
	rm /etc/rc5.d/S99onlinescreensaver
	rm /etc/rc6.d/K08onlinescreensaver
	cp /mnt/us/extensions/onlinescreensaver/bin/t1_timeout-orig /etc/kdb.src/yoshi/system/daemon/powerd/t1_timeout
	cp /mnt/us/extensions/onlinescreensaver/bin/t2_timeout-orig /etc/kdb.src/yoshi/system/daemon/powerd/t2_timeout
	/etc/init.d/powerd restart
	cp /mnt/us/linkss/backups/600x800/01N.png /mnt/us/linkss/screensavers/
	cp /mnt/us/linkss/backups/600x800/11N2.png /mnt/us/linkss/screensavers/	
fi
mntroot ro

lipc-set-prop com.lab126.cmd wirelessEnable 1

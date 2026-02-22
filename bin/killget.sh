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
#logger "killget called, ps: "
#logger "`ps -ef | grep online`"
#logger "`ps -ef | grep wget`"
PID=`ps xa | grep -m 1 "wget" | grep -v grep | awk '{ print $1 }'`

if [ -n "$PID" ]; then
     echo "killing $PID."
     logger "killing $PID"
     kill $PID || true
fi


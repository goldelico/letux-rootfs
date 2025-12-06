#!/bin/bash
# gadget config script for letux-storage-gadget
#

set -e

. /etc/gadget/core/libgadget.sh

# summary of how this script can be called:
#        * <gadget> `start
#        * <gadget> `stop
#        * <gadget> `status

if [ "$(which systemctl)" ]
then
	SERVICE=uvc@video0.service
else
	SERVICE=video0
fi

case "$1" in
	start)
		video
		if [ "$(which systemctl)" ]
		then
			systemctl start $SERVICE
		else
			daemon -r --name=$SERVICE -- /usr/bin/uvc-gadget -u /dev/$SERVICE -v uvc.0
		fi
		;;
	stop)
		if [ "$(which systemctl)" ]
		then
			systemctl stop $SERVICE
		else
			daemon --name=$SERVICE --stop 2>/dev/null
		fi
		remove_function uvc || echo failed to remove uvc gadget
		;;
	status)
		if [ "$(which systemctl)" ]
		then
			echo "$SERVICE: $(systemctl is-active $SERVICE)"
		else
			echo "$SERVICE: $(ps -ef | fgrep -v grep | fgrep -q "daemon -r --name=$SERVICE" && echo running)"
		fi
		;;
	*)
		echo "$0 called with unknown argument \`$1'" >&2
		exit 1
	;;
esac

exit 0

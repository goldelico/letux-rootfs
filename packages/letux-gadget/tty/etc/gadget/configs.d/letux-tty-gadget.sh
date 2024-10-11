#!/bin/bash
# gadget config script for letux-tty-gadget
#

set -e

. /etc/gadget/core/libgadget.sh

# summary of how this script can be called:
#        * <gadget> `start
#        * <gadget> `stop
#        * <gadget> `status

if [ "$(which systemctl)" ]
then
	SERVICE=getty@ttyGS0.service
else
	SERVICE=ttyGS0
fi

case "$1" in
	start)
		acm
		if [ "$(which systemctl)" ]
		then
			systemctl start $SERVICE
		else
			daemon -r --name=$SERVICE -- /sbin/agetty --noclear $SERVICE vt100
		fi
		;;
	stop)
		(echo; echo "Stopping USB access to terminal.") >/dev/ttyGS0
		if [ "$(which systemctl)" ]
		then
			systemctl stop $SERVICE
		else
			daemon --name=$SERVICE --stop 2>/dev/null
		fi
		remove_function acm || echo failed to remove acm gadget
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

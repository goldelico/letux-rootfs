#!/bin/bash
# gadget config script for letux-tty-gadget
#

set -e

. /etc/gadget/core/libgadget.sh

# summary of how this script can be called:
#        * <gadget> `start'
#        * <gadget> `stop'
#        * <gadget> `status'

SERVICE=getty@ttyGS0.service

case "$1" in
	start)
		acm
		if [ "$(which systemctl)" ]
		then
			systemctl start $SERVICE
		else
			daemon -r --name=$SERVICE -- /sbin/getty -L ttyGS0 115200 vt100
		fi
		;;
	stop)
		if [ "$(which systemctl)" ]
		then
			systemctl stop $SERVICE
		else
			daemon --name=$SERVICE --stop 2>/dev/null
		fi
		remove_function acm
		;;
	status)
		if [ "$(which systemctl)" ]
		then
			echo "ttyGS0": "$(systemctl is-active $SERVICE)"
		else
			echo "ttyGS0": $(ps -ef | fgrep -v grep | fgrep -q "daemon -r --name=$SERVICE" && echo running)
		fi
		;;
	*)
		echo "$0 called with unknown argument \`$1'" >&2
		exit 1
	;;
esac

exit 0

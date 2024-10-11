#!/bin/bash
# gadget config script for letux-ip-over-usb-gadget
#

set -e

. /etc/gadget/core/libgadget.sh

# summary of how this script can be called:
#        * <gadget> `start
#        * <gadget> `stop
#        * <gadget> `status

if [ "$(which systemctl)" ]
then
	SERVICE=ipousb@usb0.service
else
	SERVICE=usb0
fi


case "$1" in
	start)
		ncm
		if [ "$(which systemctl)" ]
		then
			systemctl start $SERVICE
		else
			daemon -r --name=$SERVICE -- /etc/gadget/scripts/letux-ip-over-usb-gadget-daemon.sh usb0
		fi
		;;
	stop)
		if [ "$(which systemctl)" ]
		then
			systemctl stop $SERVICE
		else
			daemon --name=$SERVICE --stop 2>/dev/null
		fi
		ifconfig usb0 down || : ignore error
		remove_function ncm || echo failed to remove ncm gadget
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

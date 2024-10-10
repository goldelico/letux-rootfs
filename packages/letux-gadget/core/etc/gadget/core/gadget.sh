#!/bin/bash -e
#
# send command to all installed gadgets
#

set -e

. /etc/gadget/core/libgadget.sh

cd /etc/gadget/configs.d

# check for no gadgets installed (?)

# do initial setup

case "$1" in
	start )
		setup_device "Letux" "$(tr -d '\0' </proc/device-tree/model)" 000001
		;;
	status )
		status
		;;
esac

# run device specific configs to setup configfs and daemons

for SCRIPT in *
	do
		./$SCRIPT "$1"
	done

# start/stop USB operation

case "$1" in
	stop )
		stop_device
		;;
	start )
		start_device
		;;
esac


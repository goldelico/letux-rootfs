#!/bin/bash -e
#
# send command to all installed gadgets
#

set -e

. /etc/gadget/core/libgadget.sh

cd /etc/gadget/configs.d

# check for no gadgets installed

case "$1" in
	stop )
		stop_device
		;;
	start )
# aus Proc/device-tree/model ableiten!
		setup_device OpenPandora RetRead 000001
		;;
esac

for SCRIPT in *
	do
		./$SCRIPT "$1"
	done

case "$1" in
	start )
		start_device
		# should start daemons only now...
		;;
esac


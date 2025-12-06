#!/bin/sh
# kFreeBSD do not accept scripts as interpreters, using #!/bin/sh and sourcing.
if [ true != "$INIT_D_SCRIPT_SOURCED" ] ; then
    set "$0" "$@"; INIT_D_SCRIPT_SOURCED=true . /lib/init/init-d-script
fi
### BEGIN INIT INFO
# Provides:          letux-gadget
# Required-Start:
# Required-Stop:
# Default-Start:     1 2 3 4 5
# Default-Stop:      0 6
# Short-Description: Start gadget service
# Description:       This script creates configfs
#                    
### END INIT INFO

# Author: H. Nikolaus Schaller <hns@goldelico.com>

. /etc/gadget/core/libgadget.sh

case "$1" in
  start)
        log_daemon_msg "Starting USB Gadget"
	# FIXME: somewhere get a unique serial number from...
	setup_device "$(cut -d ' ' -f 1 /proc/device-tree/model)" "$(cut -d ' ' -f 2- /proc/device-tree/model)" "$(echo 000001)"
	start_device
	create_configuration	# create first configuration
        log_daemon_msg "started."
        exit 0
        ;;
  restart|reload|force-reload)
        echo "Error: argument '$1' not supported" >&2
        exit 3
        ;;
  stop)
        log_daemon_msg "Stopping USB Gadget"
	stop_device
        log_progress_msg "stopped."
        log_end_msg 0
        exit 0
        ;;
  status)
	status
	exit $?
	;;
# special subcommands
  add )
	# FIXME: reject if there was no start
	$2 $3 $4
	;;
  remove )
	remove_function $2
	;;
  *)
        echo "Usage: $0 start|stop|status|add|remove" >&2
        exit 3
        ;;
esac

:

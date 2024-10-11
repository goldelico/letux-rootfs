#!/bin/bash
# gadget config script for letux-ip-over-usb-gadget
#

set -e

sleep 1

ifconfig usb0 netmask 255.255.255.192 192.168.0.202 up
route add default gw 192.168.0.200 metric 203 | : may fail
/etc/network/letux-setup-resolv-conf.sh

# needs isc-dhcp-server or busybox, udhcpd
dhcpd -f -q -cf /etc/gadget/scripts/letux-ip-over-usb-gadget-dhcpd.conf

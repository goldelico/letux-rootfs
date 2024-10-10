#!/bin/bash -e
#
# this script should be called by udev
# - on USB plugin/unplug
# - on card/cart insertion/removal
#
# Documentation:
#   https://docs.kernel.org/usb/gadget_configfs.html
#   https://elinux.org/images/e/ef/USB_Gadget_Configfs_API_0.pdf
# Code based on
#   https://stackoverflow.com/questions/42895950/usb-gadget-device-mode-configfs-uvc-and-mass-storage-on-single-configurat
#   combined with: https://gist.github.com/Gadgetoid/c52ee2e04f1cd1c0854c3e77360011e2
#   and: https://irq5.io/2016/12/22/raspberry-pi-zero-as-multiple-usb-gadgets/
#   and: https://gist.github.com/schlarpc/a327d4aa735f961555e02cbe45c11667
#   and: https://stackoverflow.com/questions/37630403/composite-usb-cdc-gadget-doesnt-work-with-windows-hosts?rq=3
# functions/$FUNCTION.$USB_IF: create the function; name must match a usb_f_<name> module such as 'acm'
# more info: https://www.usb.org/defined-class-codes
#   about testing: https://docs.kernel.org/usb/gadget-testing.html
#
# Notes:
#   there is a C Library which has similar functionality: https://github.com/linux-usb-gadgets/libusbgx

source /root/libgadget.sh

# stop application specific daemons
[ "$(which systemctl)" ] && systemctl stop getty@ttyGS0.service || daemon --name=ttyGS0.service --stop 2>/dev/null || :
ifdown usb* 2>/dev/null || :
killall hidd || :

function setup_interfaces
{ # set up all USB interfaces of this device
	rndis	# ethernet over USB for Windows
	ecm	# ethernet over USB for Mac
	acm	# USB serial Console login
	[ "$(which systemctl)" ] && systemctl start getty@ttyGS0.service || daemon -r --name=ttyGS0.service -- /sbin/getty -L ttyGS0 115200 vt100
	# uvc	# video camera emulation
#	hid	# keyboard/mouse/joystick emulation
	# FIXME: this needs a dynamic mechanism to add/remove the mass_storage on card/cart insertion/removal
	mass_storage /dev/mmcblk1 ro
# 	mass_storage /dev/slot0 ro
# 	mass_storage /dev/slot1 ro
# 	mass_storage /dev/slot2 ro

	if true
	then
		# create a 16MB "RAM"-Disk
		DISK=/tmp/usbdisk.img
		DISK=/usbdisk.img
		dd bs=1M count=16 if=/dev/zero of="$DISK"
		mkfs.vfat -F 16 -n "RAMDISK" "$DISK"
		losetup --offset 0 -f "$DISK"
		# mount disk image
		mkdir -p /media/retrode2.9
		mount -t vfat /dev/loop0 /media/retrode2.9/
		mass_storage "$DISK"
	fi
	if true
	then
		# create Retrode 32 MB file system
		DISK=/tmp/retrode3.img
		DISK=/retrode3.img
		dd bs=1M count=32 if=/dev/zero of="$DISK"
		# create single parition table
		fdisk "$DISK" >/dev/null <<END
o
n
p
1
2048

t
c
w
END
		OFFSET=$((2048*512))
		losetup --offset $OFFSET -f "$DISK"
		mkfs.vfat -n "RETRODE3" /dev/loop1
		sleep 0.5
		# mount disk image
		mkdir -p /media/retrode3
		mount -t vfat /dev/loop1 /media/retrode3/
		mass_storage "$DISK"
	fi
	if false
	then
		# give separate access to internal SD card
		mass_storage "/dev/mmcblk0p1" ro
		mass_storage "/dev/mmcblk0p2" ro
	fi
}

# main code

case "$1" in
	stop )
		cd $DEVICE 2>/dev/null
		stop_device || :	# clean up running instance
		exit;;
	remove )
		cd $DEVICE 2>/dev/null
		shift
		remove_function $1
		exit;;
	storage )
		cd $DEVICE 2>/dev/null
		shift
		mass_storage $1
		exit;;
	megadrive )
#
# FIXME: was macht ein Einstecken einer Cart?
# erscheint das als neues USB-Device
# oder erscheint das File einfach im Retrode-Device?
# letzteres ist viel einfacher zu implementieren!
# das braucht nur ein festes Setup für ein Retrode3-Disk
# und udev add/remove auf dem Slot liest/löscht die Datei
#
		# read slot header
		SLOT=/dev/slot1
		# read header: see https://plutiedev.com/rom-header
		# FIXME: verify some checksum and use "GenericSegaDrive.dat"
		NAME="$(dd if=$SLOT skip=$((0x120)) bs=1 count=48 2>/dev/null)"	# read Game name (domestic)
		NAME="$(echo $NAME | xargs)"	# trim leading, trailing and multiple spaces
		NAME="$NAME.bin"
		# FIXME: handle / or .. in $NAME!
		# FIXME: handle non-ASCII encoding
		# read SIZE from 0x1a0/0x1a4 as binary values
		ROM_START=$(xxd -p -l4 -s 0x1a0 $SLOT)
		ROM_END=$(xxd -p -l4 -s 0x1a4 $SLOT)
		SIZE=$((0x$ROM_END+1))
		# provide cart file
		# FIXME: with or without skip?
		dd if=$SLOT of="/media/retrode3/$NAME" bs=1 skip=0 count=$SIZE	# copy Game file
		echo "/media/retrode3/$NAME" >/retrode3.$(basename $SLOT)	# remember file name so that we can remove it
		# handle RAM
		;;

	* | setup )
		cd $DEVICE 2>/dev/null && stop_device || :	# clean up running instance

		[ ! -d /sys/kernel/config/usb_gadget ] && modprobe libcomposite
		mkdir -p $DEVICE && cd $DEVICE	# create new instance

		# somehow find serial number...
		setup_device OpenPandora RetRead 000001
		setup_interfaces
		start_device

		# start interfaces and daemons

		ifup $USB_IF

		# start daemons here
		# joystick
		# video

		exit
# we have no video
		sleep 1 # workaround: if gadget activated too soon, may hit a dmesg error with usb_function_activate [libcomposite]
		./uvc-gadget -d
		;;
esac

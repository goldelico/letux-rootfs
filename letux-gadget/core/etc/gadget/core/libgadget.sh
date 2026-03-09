#!/bin/sh -c echo "do not call but source this file"
# 
# this script should be sourced by a wrapper
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

DEVICE=/sys/kernel/config/usb_gadget/letux
USB_IF=usb0
USB_LANGUAGE=0x409

echo $(date) $SUBSYSTEM $ACTION "$@" >>/tmp/udev-gadget.log

gadget_status() {
	if [ ! -d $DEVICE ]
	then
		echo not initialized
		return
	fi
	echo UDC: $(cat $DEVICE/UDC 2>/dev/null)
	echo Configs: $(cd $DEVICE/configs && ls -1d * 2>/dev/null)
	echo Functions: $(cd $DEVICE/functions && ls -1d * 2>/dev/null)
	echo Files: $(cat $DEVICE/functions/mass_storage.$USB_IF/lun.*/file 2>/dev/null)
}

gadget_setup_device() {
# $1: Manufacturer
# $2: Product
# $3: Serial number
# echo gadget_setup_device
	modprobe -r g_ether || :	# may be running...
	if [ ! -d /sys/kernel/config/usb_gadget ]
	then
		modprobe libcomposite
		mount -t configfs none "$(dirname "$(dirname "$DEVICE")")" 2>/dev/null || :
	fi

	mkdir -p $DEVICE	# create new instance

	echo 0x1d6b >$DEVICE/idVendor	# Linux Foundation
	echo 0x0104 >$DEVICE/idProduct	# Multifunction Composite Gadget
	echo 0x0100 >$DEVICE/bcdDevice	# v1.0.0
	echo 0x0200 >$DEVICE/bcdUSB	# USB 2.0
	echo 0xef >$DEVICE/bDeviceClass	# USB_CLASS_MISC
	echo 0x02 >$DEVICE/bDeviceSubClass
	echo 0x01 >$DEVICE/bDeviceProtocol

	mkdir -p $DEVICE/strings/$USB_LANGUAGE
	echo "${1:-Goldelico}" >$DEVICE/strings/$USB_LANGUAGE/manufacturer
	echo "${2:-LetuxOS}" >$DEVICE/strings/$USB_LANGUAGE/product
	echo "${3:-000000}" >$DEVICE/strings/$USB_LANGUAGE/serialnumber

	echo created $(cat $DEVICE/strings/$USB_LANGUAGE/manufacturer) $(cat $DEVICE/strings/$USB_LANGUAGE/product) $(cat $DEVICE/strings/$USB_LANGUAGE/serialnumber) $DEVICE
}

gadget_shutdown_device() {
	# there is a very specific sequence to teardown the settings (start with symlinks, then configs lower level, then functions, etc.)
	find $DEVICE/os_desc/* -maxdepth 0 -type l -exec rm {} \; 2>/dev/null || :
	find $DEVICE/configs/*/* -maxdepth 0 -type l -exec rm {} \; 2>/dev/null || :
	find $DEVICE/configs/*/strings/* -maxdepth 0 -type d -exec rmdir {} \; 2>/dev/null || :
	find $DEVICE/functions/* -type d -exec rmdir {} \; 2>/dev/null || :
	find $DEVICE/strings/* -maxdepth 0 -type d -exec rmdir {} \; 2>/dev/null || :
	find $DEVICE/configs/* -maxdepth 0 -type d -exec rmdir {} \; 2>/dev/null || :
# echo device stopped.

	MOUNT="$(dirname "$(dirname "$DEVICE")")"
	umount "$MOUNT"
# echo device unmounted.
}

gadget_create_configuration() {
	for C in 1 2 3 4 5 6 7 8 9
	do
		[ "$(ls -1d $DEVICE/configs/c.$C/*.$USB_IF 2>/dev/null)" ] && continue	# find a free slot without functions
# echo gadget_create_configuration $DEVICE/configs/c.$C
		mkdir -p $DEVICE/configs/c.$C
		echo 250 >$DEVICE/configs/c.$C/MaxPower
		mkdir -p $DEVICE/configs/c.$C/strings/$USB_LANGUAGE/
		break
	done
}

gadget_bind_device() {
	[ "$(cat "$DEVICE/UDC" 2>/dev/null)" ] || ls -1 /sys/class/udc >$DEVICE/UDC
}

gadget_unbind_device() {
	if [ "$(cat "$DEVICE/UDC" 2>/dev/null)" ]
	then
		echo stop running activities
		echo "" >$DEVICE/UDC 2>/dev/null
	fi
}

gadget_stop_configuration() {
	for STORAGE in $DEVICE/functions/mass_storage.$USB_IF/lun.*/file
	do	# safely stop storage devices by setting the file name to ""
		[ -w "$STORAGE" ] && echo "" >$STORAGE
	done

	gadget_unbind_device
	# rmdir c.$C?
}

gadget_link_functions() {
	for CONFIG in $DEVICE/configs/c.*/
	do
		[ -d $CONFIG ] || continue;	# no configurations
# echo gadget_link_functions: process config $CONFIG to link configurations
		for NAME in $DEVICE/functions/*.$USB_IF
		do
# echo try $NAME
			[ -d $NAME ] || continue;	# no functions
			case $NAME in
				*/ecm.* )
					if [ -r "$CONFIG/rndis.$USB_IF" ]
					then # do not mix RNDIS and ECM in a configuration
						echo skipping $NAME in $CONFIG
						continue;
					fi
					;;
				*/rndis.* )
					if [ -r "$CONFIG/ecm.$USB_IF" ]
					then # do not mix RNDIS and ECM in a configuration
						echo skipping $NAME in $CONFIG
						continue;
					fi
					;;
			esac
# echo "$NAME" "$CONFIG/$(basename "$NAME")"
			if ! [ -r "$CONFIG/$(basename "$NAME")" ]
			then # link (new) function into config
# echo ln -sf "$NAME" "$CONFIG"
				gadget_unbind_device
				ln -sf "$NAME" "$CONFIG"
			fi
		done
	done
}

gadget_update_configuration() {
	gadget_unbind_device	# to be sure
	ANY=false
	for CONFIG in $DEVICE/configs/c.*/
	do
		[ -d $CONFIG ] || continue;	# no configurations
# echo gadget_update_configuration: process config $CONFIG to write configuration
		CONFIGURATION=""
		[ "$(ls -1d $CONFIG/acm.* 2>/dev/null)" ] && CONFIGURATION="$CONFIGURATION+CDC ACM"
		[ "$(ls -1d $CONFIG/ecm.* 2>/dev/null)" ] && CONFIGURATION="$CONFIGURATION+CDC ECM"
		[ "$(ls -1d $CONFIG/ncm.* 2>/dev/null)" ] && CONFIGURATION="$CONFIGURATION+CDC NCM"
		[ "$(ls -1d $CONFIG/rndis.* 2>/dev/null)" ] && CONFIGURATION="$CONFIGURATION+RNDIS"
		[ "$(ls -1d $CONFIG/mass_storage.* 2>/dev/null)" ] && CONFIGURATION="$CONFIGURATION+Mass Storage"
		[ "$(ls -1d $CONFIG/uvc.* 2>/dev/null)" ] && CONFIGURATION="$CONFIGURATION+Video"
		[ "$(ls -1d $CONFIG/hid.* 2>/dev/null)" ] && CONFIGURATION="$CONFIGURATION+HID"

		CONFIGURATION="${CONFIGURATION#+}"	# strip first + if any
echo "writing configuration '$CONFIGURATION'"
		mkdir -p $DEVICE/strings/$USB_LANGUAGE
		[ -w $CONFIG/strings/$USB_LANGUAGE/configuration ] && { echo "$CONFIGURATION" >$CONFIG/strings/$USB_LANGUAGE/configuration; ANY=true; }
	done
	$ANY && gadget_bind_device
}

gadget_enable_device() {
# echo gadget_enable_device
	gadget_link_functions
	gadget_update_configuration
}

gadget_disable_device() {
# echo gadget_disable_device
	# FIXME: unlink functions from all configurations?
	gadget_unbind_device

	# FIXME: do this really here?
	gadget_shutdown_device
}

gadget_host_addr() { # generate stable and unique MAC address
	(
	cd $DEVICE/strings/$USB_LANGUAGE/
	cat manufacturer product serialnumber | md5sum |
		sed 's/\(..\)\(..\)\(..\)\(..\)\(..\).*/32:\1:\2:\3:\4:\5/'	# 32: is AAI quadrant
	)
}

gadget_rndis()
{ # RNDIS Gadget usb_f_rndis
echo +++ rndis
	FUNCTION=$DEVICE/functions/rndis.$USB_IF
	mkdir -p $FUNCTION || { echo please enable CONFIG_USB_F_RNDIS in Kernel config; return 1; }

	echo 32:70:05:18:ff:78 >$FUNCTION/host_addr
	echo 46:10:3a:b3:af:d9 >$FUNCTION/dev_addr
	echo RNDIS >$FUNCTION/os_desc/interface.rndis/compatible_id
	echo 5162001 >$FUNCTION/os_desc/interface.rndis/sub_compatible_id

	# special setup for Windows
	echo 1 >$DEVICE/os_desc/use
	echo 0xcd >$DEVICE/os_desc/b_vendor_code
	echo MSFT100 >$DEVICE/os_desc/qw_sign

	# tell Windows to use this config
	ln -s $DEVICE/configs/c.$C $DEVICE/os_desc/
}

gadget_ecm()
{ # CDC ECM gadget usb_f_ecm (native) for MacOS X
echo +++ ecm
	FUNCTION=$DEVICE/functions/ecm.$USB_IF
	mkdir -p $FUNCTION || { echo please enable CONFIG_USB_F_ECM in Kernel config; return 1; }

	gadget_host_addr >$FUNCTION/host_addr
	echo 46:10:3a:b3:af:d9 >$FUNCTION/dev_addr
}

gadget_ncm()
{ # CDC NCM gadget usb_f_ncm
echo +++ ncm
	FUNCTION=$DEVICE/functions/ncm.$USB_IF
	mkdir -p $FUNCTION || { echo please enable CONFIG_USB_F_NCM in Kernel config; return 1; }

	gadget_host_addr >$FUNCTION/host_addr
	echo 46:10:3a:b3:af:d9 >$FUNCTION/dev_addr
	# os_desc?
}

gadget_acm()
{ # Serial Console usb_acm
echo +++ acm
	for NUM in 0 1 2 3 4 5 6 7 8 9
	do # find a free unused number
		[ -r $DEVICE/functions/acm.$NUM.$USB_IF ] || break
	done

	FUNCTION=$DEVICE/functions/acm.$NUM.$USB_IF
	mkdir -p $FUNCTION || { echo please enable CONFIG_USB_F_ACM in Kernel config; return 1; }
}

gadget_mass_storage() # $1=diskpath $2=ro
{ # Mass Storage usb_f_mass_storage
# $1: raw device path
echo +++ mass_storage $1 $2
	# emulate memory devices
	[ ! -e "$1" ] && { echo device not found: $1; return; }

	mkdir -p $DEVICE/functions/mass_storage.$USB_IF	# SD card access
	echo 0 >$DEVICE/functions/mass_storage.$USB_IF/stall

	for i in 0 1 2 3 4 5 6 7
	do # find an unused slot
		LUN=lun.$i
		[ -r $DEVICE/functions/mass_storage.$USB_IF/$LUN ] || break	# needs new slot with this number
		[ "$(cat $DEVICE/functions/mass_storage.$USB_IF/$LUN/file)" ] || break	# not yet connected to a file
	done

	FUNCTION=$DEVICE/functions/mass_storage.$USB_IF/$LUN
	mkdir -p $FUNCTION || { echo please enable CONFIG_USB_F_MASS_STORAGE in Kernel config; return 1; }

	echo 0 >$FUNCTION/cdrom
	echo 0 >$FUNCTION/nofua
	echo 1 >$FUNCTION/removable	# this allows empty file name to indicate device is not (yet) loaded
	[ "$2" ] && echo 1 >$FUNCTION/ro
	echo "Letux" >$FUNCTION/inquiry_string

	echo "$1" >$FUNCTION/file
}

gadget_uvc()
{ # UVC usb_f_uvc
echo +++ video
# emulates an USB Video Class device: https://developer.ridgerun.com/wiki/index.php?title=How_to_use_the_UVC_gadget_driver_in_Linux

	for NUM in 0 1 2 3 4 5 6 7 8 9
	do # find a free unused number
		[ -r $DEVICE/functions/uvc.$NUM.$USB_IF ] || break
	done

	FUNCTION=$DEVICE/functions/uvc.$NUM.$USB_IF
	FMT=$FUNCTION/streaming/mjpeg/m
	FRAME=$FMT/640x480

# FIXME: can we scan gunzip </proc/config.gz | fgrep ... for what is missing?
# but there may be no /proc/config.gz
	mkdir -p $FUNCTION || { echo please enable USB_CONFIGFS, USB_LIBCOMPOSITE, USB_CONFIGFS_F_UVC and USB_F_UVC in Kernel config; return 1; }

	mkdir -p $FRAME
	echo 640 >$FRAME/wWidth
	echo 480 >$FRAME/wHeight
	FPS=30
	INTERVAL=$((10000000/$FPS))
	echo $INTERVAL >$FRAME/dwDefaultFrameInterval
	echo $INTERVAL >$FRAME/dwFrameInterval
	echo $((640*480*2)) >$FRAME/dwMaxVideoFrameBufferSize

	echo 512 >$FUNCTION/streaming_maxpacket
	echo 0 >$FUNCTION/streaming_maxburst 2>/dev/null || true

	mkdir -p $FUNCTION/streaming/header/h
	mkdir -p $FUNCTION/control/header/h

	ln -sf $FMT $FUNCTION/streaming/header/h/m

	ln -sf $FUNCTION/streaming/header/h $FUNCTION/streaming/class/fs/h
	ln -sf $FUNCTION/streaming/header/h $FUNCTION/streaming/class/hs/h
	ln -sf $FUNCTION/streaming/header/h $FUNCTION/streaming/class/ss/h

	ln -sf $FUNCTION/control/header/h $FUNCTION/control/class/fs/h
# missing	ln -sf $FUNCTION/control/header/h $FUNCTION/control/class/hs
	ln -sf $FUNCTION/control/header/h $FUNCTION/control/class/ss/h

	# userspace should now be able to write to /dev/uvc* (a symlink to be created by udevd) to send over USB
	# use uvd-gadget to stream video
}

gadget_hid()
{ # HID: usb_f_hid
# $1: type (keyboard, mouse, gamepad, joystick)
echo +++ hid $1
	# emulate HID device: https://github.com/qlyoung/keyboard-gadget/blob/master/gadget-setup.sh
	# or https://randomnerdtutorials.com/raspberry-pi-zero-usb-keyboard-hid/
	# Device class: https://www.usb.org/sites/default/files/hid1_11.pdf
	for NUM in 0 1 2 3 4 5 6 7 8 9
	do # find a free unused number
		[ -r $DEVICE/functions/hid.$NUM.$USB_IF ] || break
	done

	FUNCTION=$DEVICE/functions/hid.$NUM.$USB_IF
	mkdir -p $FUNCTION || { echo please enable USB_CONFIGFS, USB_LIBCOMPOSITE, CONFIG_USB_CONFIGFS_F_HID and CONFIG_USB_F_HID in Kernel config; return 1; }

	case "$1" in
	keyboard )
		echo 1 >$FUNCTION/protocol		# 1 for keyboard. see usb spec
		echo 1 >$FUNCTION/subclass		# set the device subclass
		echo 8 >$FUNCTION/report_length	# number of bytes per report
		cat <<EOF | xxd -r -p >$FUNCTION/report_desc
05010906a101050719e029e715002501
75019508810295017508810195057501
05081901290591029501750391019506
7508150025650507190029658100c0
EOF
		;;
	mouse )
		echo 2 >$FUNCTION/protocol		# 2 for mouse. see usb spec
		echo 1 >$FUNCTION/subclass		# set the device subclass
		echo 4 >$FUNCTION/report_length	# number of bytes per report
		cat <<EOF | xxd -r -p >$FUNCTION/report_desc
05010902a1010901a100050919012903
15002501950375018102950175058101
0501093009311581257f750895028106
c0c0
EOF
		;;
	gamepad | joystick )
		echo 0 >$FUNCTION/protocol		# 0 for joystick. see usb spec
		echo 0 >$FUNCTION/subclass		# set the device subclass
		echo 4 >$FUNCTION/report_length	# number of bytes per report
		cat <<EOF | xxd -r -p >$FUNCTION/report_desc
0501        # Usage Page (Generic Desktop)
0905        # Usage (Gamepad)
a101        # Collection (Application)
0509        # Usage Page (Button)
1901        # Usage Minimum (Button 1)
2902        # Usage Maximum (Button 2)
1500        # Logical Minimum (0)
2501        # Logical Maximum (1)
9502        # Report Count (2)
7501        # Report Size (1)
8102        # Input (Data,Var,Abs)
9506        # Report Count (6)
7501        # Report Size (1)
8101        # Input (Const,Arr,Abs) - padding
0501        # Usage Page (Generic Desktop)
0930        # Usage (X)
0931        # Usage (Y)
1581        # Logical Minimum (-127)
257f        # Logical Maximum (127)
7508        # Report Size (8)
9502        # Report Count (2)
8102        # Input (Data,Var,Abs)
c0          # End Collection
EOF
		;;
	* )
		echo unknown device type: $1
		rmdir $FUNCTION
		return 1
	esac

	# userspace should now be able to write to /dev/hidg* to send over USB
	# well, since the joystick itself is a /dev (or should be) we need a daemon to pipe: cat </dev/joystick >/dev/hidg - and avoid buffering
	# but: we must then translate Linux device events to USB keyboard/joystick messages
}

gadget_remove() # $1=functionname
{ # delete a function (all instances) from running system
echo --- remove $1

	for CONFIG in $DEVICE/configs/c.*/
	do
#echo $0: process config $CONFIG
#echo		rm -f $CONFIG/$1.$USB_IF	# remove symlink to config (i.e. disconnect function)
		rm -f $CONFIG/$1*.$USB_IF	# remove symlink to config (i.e. disconnect function)
	done

	for DEV in $DEVICE/functions/$1*.$USB_IF
	do
		case "$1" in
			uvc )
				rm $DEV/control/class/*/h
				rm $DEV/streaming/class/*/h
				rm $DEV/streaming/header/h/m
				rm $DEV/control/header/h
				rm $DEV/streaming/header/h
				rm -R $DEV/streaming/mjpeg/m/*
				rm $DEV/streaming/mjpeg/m
				;;			
			# safely stop storage devices by setting the file name to ""?
		esac
		[ -d $DEV ] && rmdir $DEV	# remove function (we can't remove function first!)
	done
}

# EOF
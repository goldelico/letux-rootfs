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

status() {
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

setup_device() {
# $1: Manufacturer
# $2: Product
# $3: Serial number
echo setup_device
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
}

create_configuration() {
	for C in 1 2 3 4 5 6 7 8 9
	do
		[ -r $DEVICE/configs/c.$C ] && continue	# find a free slot
echo create_configuration $C
		mkdir -p $DEVICE/configs/c.$C
		echo 250 >$DEVICE/configs/c.$C/MaxPower
		mkdir -p $DEVICE/configs/c.$C/strings/$USB_LANGUAGE/
		break
	done
}

link_functions() {
	for CONFIG in $DEVICE/configs/c.*/
	do
		[ -d $CONFIG ] || continue;	# no configurarations
echo process config $CONFIG to link configurations
		for NAME in $DEVICE/functions/*.$USB_IF
		do
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
			ln -sf "$NAME" "$CONFIG"
		done
	done
}

update_configuration() {
	ANY=false
	for CONFIG in $DEVICE/configs/c.*/
	do
		[ -d $CONFIG ] || continue;	# no configurarations
echo process config $CONFIG to write configuration
		CONFIGURATION=""
		for NAME in $DEVICE/functions/*.$USB_IF
		do
			[ -d $NAME ] || continue;	# not found
echo try function $NAME
# CHECKME: do we need this at all? Does anyone care about this string?
			case $NAME in
				*/acm.* )
					CONFIGURATION="$CONFIGURATION+CDC ACM"
					;;
				*/ecm.* )
					CONFIGURATION="$CONFIGURATION+CDC ECM"
					;;
				*/ncm.* )
					CONFIGURATION="$CONFIGURATION+CDC NCM"
					;;
				*/rndis.* )
					CONFIGURATION="$CONFIGURATION+RNDIS"
					;;
				*/mass_storage.* )
					CONFIGURATION="$CONFIGURATION+Mass Storage"
					;;
				*/uvc.* )
					CONFIGURATION="$CONFIGURATION+Video"
					;;
				*/hid.* )
					CONFIGURATION="$CONFIGURATION+HID"
					;;
				* ) echo unknown function "$NAME"
					exit 1
					;;
			esac
		done
echo "writing configuration '$CONFIGURATION'"
		mkdir -p $DEVICE/strings/$USB_LANGUAGE
		[ -w $CONFIG/strings/$USB_LANGUAGE/configuration ] && { echo ${CONFIGURATION#+} >$CONFIG/strings/$USB_LANGUAGE/configuration; ANY=true; }
	done
	if $ANY
	then
		ls -1 /sys/class/udc >$DEVICE/UDC
	else
		[ -r "$DEVICE/UDC" -a "$(cat "$DEVICE/UDC")" ] && { echo stop running activities; echo "" >$DEVICE/UDC; } || :
	fi	
}

start_device() {
echo start_device
	link_functions
	update_configuration
}

stop_device() {
echo stop_device
	for STORAGE in $DEVICE/functions/mass_storage.$USB_IF/lun.*/file
	do	# safely stop storage devices by setting the file name to ""
		[ -w "$STORAGE" ] && echo "" >$STORAGE
	done

	[ -r "$DEVICE/UDC" -a "$(cat "$DEVICE/UDC")" ] && { echo stop running activities; echo "" >$DEVICE/UDC; } || :

	# there is a very specific sequence to teardown the settings (start with symlinks, then configs lower level, then functions, etc.)
	find $DEVICE/os_desc/* -maxdepth 0 -type l -exec rm {} \; 2>/dev/null || :
	find $DEVICE/configs/*/* -maxdepth 0 -type l -exec rm {} \; 2>/dev/null || :
	find $DEVICE/configs/*/strings/* -maxdepth 0 -type d -exec rmdir {} \; 2>/dev/null || :
	find $DEVICE/functions/* -type d -exec rmdir {} \; 2>/dev/null || :
	find $DEVICE/strings/* -maxdepth 0 -type d -exec rmdir {} \; 2>/dev/null || :
	find $DEVICE/configs/* -maxdepth 0 -type d -exec rmdir {} \; 2>/dev/null || :
echo device stopped.

	MOUNT="$(dirname "$(dirname "$DEVICE")")"
	umount "$MOUNT"
echo device unmounted.
}

host_addr() { # generate stable and unique MAC address
	(
	cd $DEVICE/strings/$USB_LANGUAGE/
	cat manufacturer product serialnumber | md5sum |
		sed 's/\(..\)\(..\)\(..\)\(..\)\(..\).*/32:\1:\2:\3:\4:\5/'	# 32: is AAI quadrant
	)
}

rndis()
{ # RNDIS Gadget usb_f_rndis
echo +++ rndis
	mkdir -p $DEVICE/functions/rndis.$USB_IF  # network

	echo 32:70:05:18:ff:78 >$DEVICE/functions/rndis.$USB_IF/host_addr
	echo 46:10:3a:b3:af:d9 >$DEVICE/functions/rndis.$USB_IF/dev_addr
	echo RNDIS >$DEVICE/functions/rndis.$USB_IF/os_desc/interface.rndis/compatible_id
	echo 5162001 >$DEVICE/functions/rndis.$USB_IF/os_desc/interface.rndis/sub_compatible_id

	# special setup for Windows
	echo 1 >$DEVICE/os_desc/use
	echo 0xcd >$DEVICE/os_desc/b_vendor_code
	echo MSFT100 >$DEVICE/os_desc/qw_sign

	# tell Windows to use this config
	ln -s $DEVICE/configs/c.$C $DEVICE/os_desc/
	start_device
}

ecm()
{ # CDC ECM gadget usb_f_ecm (native) for MacOS X
echo +++ ecm
	mkdir -p $DEVICE/functions/ecm.$USB_IF  # network

	echo 32:70:05:18:ff:78 >$DEVICE/functions/ecm.$USB_IF/host_addr
	echo 46:10:3a:b3:af:d9 >$DEVICE/functions/ecm.$USB_IF/dev_addr
	start_device
}

ncm()
{ # CDC NCM gadget usb_f_ncm
echo +++ ncm
	mkdir -p $DEVICE/functions/ncm.$USB_IF  # network

#	echo 32:70:05:18:ff:78 >$DEVICE/functions/ncm.$USB_IF/host_addr
	host_addr >$DEVICE/functions/ncm.$USB_IF/host_addr
	echo 46:10:3a:b3:af:d9 >$DEVICE/functions/ncm.$USB_IF/dev_addr
	# os_desc?
	start_device
}

acm()
{ # Serial Console usb_acm_rndis
echo +++ acm
	mkdir -p $DEVICE/functions/acm.$USB_IF  # network
	start_device
}

mass_storage() # $1=diskpath $2=ro
{ # Mass Storage usb_f_mass_storage
# $1: raw device path
echo +++ mass_storage
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

	mkdir -p $DEVICE/functions/mass_storage.$USB_IF/$LUN

	echo 0 >$DEVICE/functions/mass_storage.$USB_IF/$LUN/cdrom
	echo 0 >$DEVICE/functions/mass_storage.$USB_IF/$LUN/nofua
	echo 1 >$DEVICE/functions/mass_storage.$USB_IF/$LUN/removable	# this allows empty file name to indicate device is not (yet) loaded
	[ "$2" ] && echo 1 >$DEVICE/functions/mass_storage.$USB_IF/$LUN/ro
	echo "Letux" >$DEVICE/functions/mass_storage.$USB_IF/$LUN/inquiry_string

	echo "$1" >$DEVICE/functions/mass_storage.$USB_IF/$LUN/file
}

video()
{ # UVC usb_f_uvc
echo +++ video
# emulates an USB Video Class device: https://developer.ridgerun.com/wiki/index.php?title=How_to_use_the_UVC_gadget_driver_in_Linux
	mkdir -p $DEVICE/functions/uvc.$USB_IF  # video

	mkdir -p $DEVICE/functions/uvc.$USB_IF/control/header/h
	(cd $DEVICE/functions/uvc.$USB_IF/control/ && ln -sf header/h class/fs)
	mkdir -p $DEVICE/functions/uvc.$USB_IF/streaming/uncompressed/u/360p
	cat <<EOF >$DEVICE/functions/uvc.$USB_IF/streaming/uncompressed/u/360p/dwFrameInterval
666666
1000000
5000000
EOF
	mkdir $DEVICE/functions/uvc.$USB_IF/streaming/header/h
	(cd $DEVICE/functions/uvc.$USB_IF/streaming/header/h && ln -sf ../../uncompressed/u)
	(cd $DEVICE/functions/uvc.$USB_IF/control/class/fs && ln -sf ../../header/h)
	(cd $DEVICE/functions/uvc.$USB_IF/control/class/hs && ln -sf ../../header/h)
}

hid()
{ # HID: usb_f_hid
# $1: protocol
# $2: sibclass
# $3: bytes per report
# $4: descriptor (hex string)
echo +++ hid
	# emulate HID device: https://github.com/qlyoung/keyboard-gadget/blob/master/gadget-setup.sh
	# or https://randomnerdtutorials.com/raspberry-pi-zero-usb-keyboard-hid/
	# Device class: https://www.usb.org/sites/default/files/hid1_11.pdf
	mkdir -p $DEVICE/functions/hid.$USB_IF 	# hid device

	for i in 0 1 2 3 4 5 6 7
	do
		LUN=lun.$i
		[ -r $DEVICE/functions/hid.$USB_IF/$LUN ] || break
	done

# FIXME: allow to add multiple devices

	# this makes a keyboard
	echo ${1:-1} >$DEVICE/functions/hid.$USB_IF/protocol		# 1 for keyboard. see usb spec
	echo ${2:-1} >$DEVICE/functions/hid.$USB_IF/subclass		# set the device subclass
	echo ${3:-8} >$DEVICE/functions/hid.$USB_IF/report_length	# number of bytes per report
	DEFAULT=$(
		echo "00: 0501 0906 a101 0507 19e0 29e7 1500 2501"
		echo "10: 7501 9508 8102 9501 7508 8103 9505 7501"
		echo "20: 0508 1901 2905 9102 9501 7503 9103 9506"
		echo "30: 7508 1500 2565 0507 1900 2965 8100 c0"
	)
	echo "${4:-$DEFAULT}" | xxd -r >$DEVICE/functions/hid.$USB_IF/report_desc	# write the binary blob of the report descriptor to report_desc; see HID class spec

	# userspace should now be able to write to /dev/hidg* to send over USB
	# well, since the joystick itself is a /dev (or should be) we need a daemon to pipe: cat </dev/joystick >/dev/hidg - and avoid buffering
	# but: we must then translate Linux device events to USB keyboard/joystick messages
}

remove_function() # $1=functionname
{ # delete a function from running system
echo remove_function $1
	for CONFIG in $DEVICE/configs/c.*/
	do
#echo $0: process config $CONFIG
#echo		rm -f $CONFIG/$1.$USB_IF	# remove symlink to config (i.e. disconnect function)
		rm -f $CONFIG/$1.$USB_IF	# remove symlink to config (i.e. disconnect function)
	done

	rmdir $DEVICE/functions/$1.$USB_IF	# remove function (we can't remove function first!)

	update_configuration || : ignore error
}

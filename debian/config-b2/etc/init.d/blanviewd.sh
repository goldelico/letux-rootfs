#! /bin/sh
# /etc/init.d/blanviewd.sh
#
# run blanview daemon for OpenPhoenux 3704
# it will read the ambient light sensor and dim
# the backlight intensity in bright environmental light
#
exit 1
# Some things that run always

# Carry out specific functions when asked to by the system
case "$1" in
 start)
       cd /root
       [ -x blanviewd ] || make blanviewd
       ./blanviewd &
   ;;
 stop)
       killall blanviewd
   ;;
 *)
   echo "Usage: /etc/init.d/blanviewd.sh {start|stop}"
   exit 1
   ;;
esac

exit 0

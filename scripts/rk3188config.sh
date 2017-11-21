#!/bin/bash

PATCH=$(cat /patch)

# This script will be run in chroot under qemu.

echo "Creating \"fstab\""
echo "# Rk3188 fstab" > /etc/fstab
echo "" >> /etc/fstab
echo "proc            /proc           proc    defaults        0       0
tmpfs   /var/log                tmpfs   size=20M,nodev,uid=1000,mode=0777,gid=4, 0 0
tmpfs   /var/spool/cups         tmpfs   defaults,noatime,mode=0755 0 0
tmpfs   /var/spool/cups/tmp     tmpfs   defaults,noatime,mode=0755 0 0
tmpfs   /tmp                    tmpfs   defaults,noatime,mode=0755 0 0
tmpfs   /dev/shm                tmpfs   defaults,nosuid,noexec,nodev        0 0
" > /etc/fstab

#echo "Adding default sound modules"
#echo "
#
#" >> /etc/modules

echo "#!/bin/sh -e
if [ -f /first_boot ] ; then
rm -f /first_boot
fi
exit 0" > /etc/rc.local

echo "Installing additonal packages"
apt-get update
apt-get -y install liblircclient0 lirc
apt-get -y install winbind libnss-winbind tar bzip2

echo "Cleaning APT Cache and remove policy file"
rm -f /var/lib/apt/lists/*archive*
apt-get clean

#On The Fly Patch
if [ "$PATCH" = "volumio" ]; then
echo "No Patch To Apply"
else
echo "Applying Patch ${PATCH}"
PATCHPATH=/${PATCH}
cd $PATCHPATH
#Check the existence of patch script
if [ -f "patch.sh" ]; then
sh patch.sh
else
echo "Cannot Find Patch File, aborting"
fi
cd /
rm -rf ${PATCH}
fi
rm /patch

rm /usr/sbin/policy-rc.d

echo "Installing modules and firmwares"
cd /
tar xjvfp /modules.tar.bz2
tar xjvfp /firmwares.tar.bz2
rm /modules.tar.bz2 /firmwares.tar.bz2

# singal to resize root file system partition
touch /first_boot

cat > /etc/init/serial.conf << _EOF_
# ttyS0 - getty
#
# This service maintains a getty on ttyS0 from the point the system is
# started until it is shut down again.

start on stopped rc or RUNLEVEL=[12345]
stop on runlevel [!12345]

respawn
exec /sbin/getty -L 115200 console vt102
_EOF_

echo "Adding group for android kernel"
groupadd -g 3003 inet
groupadd -g 3004 net_raw

echo "Adding user to group"
for user in `cut -d: -f1 /etc/passwd`
do
    usermod -a -G inet $user
    usermod -a -G net_raw $user
done

echo "Config network for RK3188/AP6210"
# AP6210 in this system only support wext
sed -i 's/-Dnl80211,wext/-Dwext/g' /volumio/app/plugins/system_controller/network/wireless.js

#there is no eth0
sed -i 's/eth0/wlan0/g' /volumio/app/plugins/system_controller/system/index.js

#change op_mode parameter of bcmdhd and restart
sed -i '/echo "Launching Ordinary Hostapd"/a#change bcmdhd.op_mode and restart \necho 2 > /sys/module/bcmdhd/parameters/op_mode\nrfkill block wifi\nrfkill unblock wifi' /bin/hotspot.sh
sed -i "/\/usr\/bin\/sudo \/usr\/bin\/killall dhcpd/a#change bcmdhd.op_mode and restart\necho 0 > /sys/module/bcmdhd/parameters/op_mode\nrfkill block wifi\nrfkill unblock wifi" /bin/hotspot.sh

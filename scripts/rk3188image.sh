#!/bin/sh

# Default build for Debian 32bit
ARCH="armv7"

while getopts ":d:v:p:" opt; do
  case $opt in
    v)
      VERSION=$OPTARG
      ;;
    p)
      PATCH=$OPTARG
      ;;
  esac
done

BUILDDATE=$(date -I)
IMG_FILE="Volumio${VERSION}-${BUILDDATE}-rk3188.img"

if [ "$ARCH" = arm ]; then
  DISTRO="Raspbian"
else
  DISTRO="Debian 32bit"
fi

echo "Creating Image File ${IMG_FILE} with $DISTRO rootfs"
dd if=/dev/zero of=system.img bs=1M count=800

echo "Creating new filesystem on system.img ..."
mkfs -F -t ext4 -L linuxroot system.img #> /dev/null 2>&1
sync

echo "Preparing for the Rockchip RK3188 kernel/platform files"
if [ -d platform-rk3188 ]
then
	echo "Platform folder already exists - keeping it"
    # if you really want to re-clone from the repo, then delete the platform-asus folder
    # that will refresh all the asus platforms, see below
else
	echo "Clone RK3188 platform files from repo"
	git clone https://github.com/trlsmax/platform-rk3188.git platform-rk3188
	echo "Unpack the RK3188 platform files"
	cd platform-rk3188
	tar xfJ rk3188.tar.xz
        chmod +x ./afptool
        chmod +x ./img_maker
	cd ..
fi

if [ -d /mnt ]
then
	echo "/mount folder exist"
else
	mkdir /mnt
fi
if [ -d /mnt/volumio ]
then
	echo "Volumio Temp Directory Exists - Cleaning it"
	rm -rf /mnt/volumio/*
else
	echo "Creating Volumio Temp Directory"
	sudo mkdir /mnt/volumio
fi

echo "Creating mount point for the images partition"
mount -o loop system.img /mnt/volumio

echo "Copying Volumio RootFs"
cp -pdR build/$ARCH/root/* /mnt/volumio

echo "Copying Rk3188 modules and firmware"
cp -pdR platform-rk3188/modules.tar.bz2 /mnt/volumio
cp -pdR platform-rk3188/firmwares.tar.bz2 /mnt/volumio
sync

echo "Preparing to run chroot for more RK3188 configuration"
cp scripts/rk3188config.sh /mnt/volumio

mount /dev /mnt/volumio/dev -o bind
mount /proc /mnt/volumio/proc -t proc
mount /sys /mnt/volumio/sys -t sysfs
echo $PATCH > /mnt/volumio/patch

chroot /mnt/volumio /bin/bash -x <<'EOF'
su -
/rk3188config.sh
EOF

#cleanup
rm /mnt/volumio/rk3188config.sh

echo "Unmounting Temp devices"
umount -l /mnt/volumio/dev
umount -l /mnt/volumio/proc
umount -l /mnt/volumio/sys

echo "==> RK3188 device installed"

#echo "Removing temporary platform files"
#echo "(you can keep it safely as long as you're sure of no changes)"
#rm -r platform-rk3188
sync

echo "Unmounting Temp Devices"
umount -l /mnt/volumio

dmsetup remove_all
sync

echo "start to build the image"
mv system.img ./platform-rk3188/images/
./platform-rk3188/afptool -pack ./platform-rk3188/images ./tmp.img
./platform-rk3188/img_maker ./platform-rk3188/images/RK3188Loader\(L\)_V2.19.bin ./tmp.img ./${IMG_FILE}
rm -rf ./tmp.img ./platform-rk3188/images/system.img

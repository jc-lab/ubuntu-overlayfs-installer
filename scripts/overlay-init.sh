#!/bin/sh

fail(){
    echo -e "$1"
    bash
    exit 1
}

warn(){
    echo -e "$1"
}

echo "mount: "
mount

echo "fdisk: "
fdisk -l

echo "blkid: "
blkid

sleep 1

# load module
modprobe overlay
if [ $? -ne 0 ]; then
    warn "ERROR: missing overlay kernel module"
fi

mount -v -n -t proc  -onodev,noexec,nosuid proc  /proc
if [ $? -ne 0 ]; then
    warn "ERROR: could not mount proc"
fi

mount -v -n -t sysfs -onodev,noexec,nosuid sysfs /sys
if [ $? -ne 0 ]; then
    warn "ERROR: could not mount sys"
fi

ROOTFS_UPPER_MNT=/mnt/upper
ROOTFS_UPPER_DATA=/mnt/upper/upper
ROOTFS_UPPER_WORK=/mnt/upper/work
ROOTFS_LOWER=/mnt/lower
ROOTFS_NEW=/mnt/new
ROOTFS_TMP=/mnt
ROOTFS_UPPER_DEV=LABEL=rootfs-upper

ROOTFS_LOWER_MOUNT_LINE=$(mount | awk '/on \/ /')
ROOTFS_LOWER_DEV=$(echo $ROOTFS_LOWER_MOUNT_LINE | awk '{print $1}')
ROOTFS_LOWER_FS=$(echo $ROOTFS_LOWER_MOUNT_LINE | awk '{print $5}')

mount -t tmpfs tmpfs /mnt
mkdir -p $ROOTFS_UPPER_MNT $ROOTFS_LOWER $ROOTFS_NEW

mount -t $ROOTFS_LOWER_FS -o ro $ROOTFS_LOWER_DEV $ROOTFS_LOWER
mount -t ext4 $ROOTFS_UPPER_DEV $ROOTFS_UPPER_MNT

mkdir -p $ROOTFS_UPPER_DATA
mkdir -p $ROOTFS_UPPER_WORK
mkdir -p $ROOTFS_UPPER_MNT/data/var/lib/containerd

mount -t overlay -o lowerdir=$ROOTFS_LOWER,upperdir=$ROOTFS_UPPER_DATA,workdir=$ROOTFS_UPPER_WORK overlayfs-root $ROOTFS_NEW
if [ $? -ne 0 ]; then
    fail "ERROR: could not mount overlayFS"
fi

mount --bind /proc $ROOTFS_NEW/proc

cd $ROOTFS_NEW
pivot_root . .$ROOTFS_TMP
exec chroot . sh -c "$(cat <<'END'
ROOTFS_TMP=/mnt
ROOTFS_UPPER_MNT=/mnt/upper
ROOTFS_LOWER=/mnt/lower

# move ro and rw mounts to the new root
mount --move $ROOTFS_TMP$ROOTFS_LOWER /.rootfs.ro
if [ $? -ne 0 ]; then
    echo "ERROR: could not move ro-root into newroot"
    /bin/bash
fi

mount --move $ROOTFS_TMP$ROOTFS_UPPER_MNT /.rootfs.rw
if [ $? -ne 0 ]; then
    echo "ERROR: could not move tempfs rw mount into newroot"
    /bin/bash
fi

[ ! -d /var/lib/cloud/seed/nocloud-net ] && mkdir -p /var/lib/cloud/seed/nocloud-net
mkdir -p /var/lib/
cp /.rootfs.rw/cloud/* /var/lib/cloud/seed/nocloud-net/

mount --move $ROOTFS_TMP/dev /dev
mount --move $ROOTFS_TMP/sys /sys

echo "START TMP ROOTFS UNMOUNT"
# unmount unneeded mounts so we can unmout the old readonly root
for path in $(mount | awk '/on \/mnt\// {print $3}' | sort -u -r); do
  echo umount $path
  umount $path
done
umount $ROOTFS_TMP

# continue with regular init
exec /sbin/init
END
)"


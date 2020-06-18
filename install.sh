#!/bin/bash

DEVICE=$1
ROOTFS_SQSH_FILE=./out/rootfs.sqfs

TEMP_DIR=/tmp/installer

BOOT_PART=${DEVICE}1
ROOTFS_PART=${DEVICE}2
UPPER_PART=${DEVICE}3

TEMP_BOOT=$TEMP_DIR/boot
TEMP_ROOTFS=$TEMP_DIR/rootfs.ro
TEMP_UPPER=$TEMP_DIR/rootfs.rw
TEMP_OVERLAY=$TEMP_DIR/rootfs.merge

MOUNT_LIST=""
function push_mount () {
  MOUNT_LIST="$1 $MOUNT_LIST"
}

while :
do
  echo "Enter hostname: "
  read TARGET_HOSTNAME
  if [ -n "$TARGET_HOSTNAME" ]; then
    break
  fi
done

echo "HOSTNAME=$TARGET_HOSTNAME"

rm -rf $TEMP_DIR
mkdir -p $TEMP_BOOT $TEMP_ROOTFS $TEMP_OVERLAY $TEMP_UPPER

ROOTFS_SQFS_SIZE=$(stat -c%s $ROOTFS_SQSH_FILE)

BOOT_PART_SIZE=$(( 256 * 1024 ))
ROOTFS_PART_SIZE=$(( ROOTFS_SQFS_SIZE / 1024 + 4096 ))
DATA_PART_SIZE=$(( 256 * 1024 ))

TOTAL_SIZE=$((BOOT_PART_SIZE + ROOTFS_PART_SIZE + DATA_PART_SIZE))
TOTAL_SIZE_BYTES=$((TOTAL_SIZE * 1024))

dd if=/dev/zero of=$DEVICE bs=512 count=1
printf "g\nn\np\n\n\n+${BOOT_PART_SIZE}K\nn\np\n\n\n+${ROOTFS_PART_SIZE}K\nn\np\n\n\n\nt\n1\n1\n\nw\n" | fdisk $DEVICE

echo "fdisk: DONE"

echo "check device..."

function checkDevice() {
  dev=$1
  count=0
  while [[ ! -b $dev && $count -lt 5 ]]; do
    echo "device: $dev: IS NOT READY"
    sleep 1
    count=$(( count + 1 ))
  done
  [ -b $dev ] && return 0 || return 1
}

if ! checkDevice $BOOT_PART; then
  echo "Could not find BOOT_PART ($BOOT_PART)!"
  exit 1
fi

if ! checkDevice $ROOTFS_PART; then
  echo "Could not find ROOTFS_PART ($ROOTFS_PART)!"
  exit 1
fi

if ! checkDevice $UPPER_PART; then
  echo "Could not find UPPER_PART ($UPPER_PART)!"
  exit 1
fi

mkfs -t vfat -n boot $BOOT_PART
mkfs -t ext4 -F -L rootfs-upper $UPPER_PART
dd if=$ROOTFS_SQSH_FILE of=$ROOTFS_PART bs=131072 status=progress

mount -t squashfs $ROOTFS_PART $TEMP_ROOTFS
push_mount $TEMP_ROOTFS

mount $UPPER_PART $TEMP_UPPER
push_mount $TEMP_UPPER

mkdir -p $TEMP_UPPER/upper
mkdir -p $TEMP_UPPER/work

cp -rfL $TEMP_ROOTFS/boot/* $TEMP_BOOT

echo "Mount EFI partition"
mkdir -p ${TEMP_ROOTFS}/boot
mount $BOOT_PART ${TEMP_ROOTFS}/boot
push_mount $TEMP_ROOTFS/boot

cp -arf -L $TEMP_BOOT/* ${TEMP_ROOTFS}/boot/

echo "Get ready for chroot"
mount --bind /dev ${TEMP_ROOTFS}/dev
push_mount ${TEMP_ROOTFS}/dev
mount -t devpts /dev/pts ${TEMP_ROOTFS}/dev/pts
push_mount ${TEMP_ROOTFS}/dev/pts
mount -t proc proc ${TEMP_ROOTFS}/proc
push_mount ${TEMP_ROOTFS}/proc
mount -t sysfs sysfs ${TEMP_ROOTFS}/sys
push_mount ${TEMP_ROOTFS}/sys
mount -t tmpfs tmpfs ${TEMP_ROOTFS}/tmp
push_mount ${TEMP_ROOTFS}/tmp

cp ./grub-mkconfig.sh ${TEMP_ROOTFS}/boot/grub-mkconfig.sh
chmod +x ${TEMP_ROOTFS}/boot/grub-mkconfig.sh

cp -rf ${TEMP_ROOTFS}/etc/grub.d ${TEMP_ROOTFS}/tmp/grub.d
mount -t tmpfs tmpfs ${TEMP_ROOTFS}/etc/grub.d
push_mount ${TEMP_ROOTFS}/etc/grub.d
cp -rf ${TEMP_ROOTFS}/tmp/grub.d/* ${TEMP_ROOTFS}/etc/grub.d/

echo "Entering chroot, installing Linux kernel and Grub"
cat << 'EOF' | chroot ${TEMP_ROOTFS}
  set -e
  export HOME=/root
  export DEBIAN_FRONTEND=noninteractive
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ubuntu --recheck --no-nvram --removable
  update-grub2
EOF

grub_probe="chroot $TEMP_ROOTFS grub-probe"
GRUB_DEVICE_BOOT="`${grub_probe} --target=device /boot`"
GRUB_DEVICE_BOOT_UUID="`${grub_probe} --device ${GRUB_DEVICE_BOOT} --target=fs_uuid 2> /dev/null`" || true

if [ -n $GRUB_DEVICE_BOOT_UUID ]; then
  GRUB_DEVICE_BOOT_TARGET=UUID=$GRUB_DEVICE_BOOT_UUID
else
  GRUB_DEVICE_BOOT_TARGET=$GRUB_DEVICE_BOOT
fi

mount -t overlay -o lowerdir=$TEMP_ROOTFS,upperdir=$TEMP_UPPER/upper,workdir=$TEMP_UPPER/work overlayfs-root $TEMP_OVERLAY
push_mount $TEMP_OVERLAY

echo "$GRUB_DEVICE_BOOT_TARGET /boot vfat defaults,uid=0,gid=0,umask=333 0 0" >> $TEMP_OVERLAY/etc/fstab
echo "/.rootfs.rw/data/var/lib/containerd /var/lib/containerd none bind,defaults 0 0" >> $TEMP_OVERLAY/etc/fstab

mkdir -p $TEMP_OVERLAY/var/lib/cloud/seed/nocloud-net
CLOUD_METADATA_FILE=$TEMP_OVERLAY/var/lib/cloud/seed/nocloud-net/meta-data

echo "instance-id: $(uuidgen)" > $CLOUD_METADATA_FILE
echo "local-hostname: $TARGET_HOSTNAME" >> $CLOUD_METADATA_FILE

echo "Unmounting filesystems"
for a in $MOUNT_LIST
do
  umount $a
done


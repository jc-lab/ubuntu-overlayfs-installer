FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive

RUN echo '\n\
deb mirror://mirrors.ubuntu.com/mirrors.txt focal main restricted universe multiverse\n\
deb mirror://mirrors.ubuntu.com/mirrors.txt focal-updates main restricted universe multiverse\n\
deb mirror://mirrors.ubuntu.com/mirrors.txt focal-backports main restricted universe multiverse\n\
deb mirror://mirrors.ubuntu.com/mirrors.txt focal-security main restricted universe multiverse\n\
' > /tmp/apt.mirror.sources.list && \
    cat /tmp/apt.mirror.sources.list > /tmp/apt.sources.list && \
    cat /tmp/apt.sources.list > /etc/apt/sources.list

RUN apt-get update -y && \
    apt-get install -y curl xz-utils unzip dump squashfs-tools qemu-user-static binfmt-support dosfstools debootstrap

ENV ROOTFS_PATH=/work/rootfs

RUN mkdir -p $ROOTFS_PATH && \
    APT_REPO=$(curl http://mirrors.ubuntu.com/mirrors.txt | head -n 1) && \
    debootstrap --arch amd64 focal $ROOTFS_PATH $APT_REPO && \
    cp -f /tmp/apt.mirror.sources.list $ROOTFS_PATH/etc/apt/sources.list

COPY ["./scripts/prebuild.sh", "/work/scripts/prebuild.sh"]
RUN cp /work/scripts/prebuild.sh $ROOTFS_PATH/prebuild.sh && \
    chmod +x $ROOTFS_PATH/prebuild.sh && \
    chroot $ROOTFS_PATH /prebuild.sh && \
    rm $ROOTFS_PATH/prebuild.sh

RUN rm -f $ROOTFS_PATH/etc/ssh/*key* && \
    mkdir -p $ROOTFS_PATH/var/lib/os-prober/mount && \
    mkdir -p $ROOTFS_PATH/.rootfs.ro $ROOTFS_PATH/.rootfs.rw

COPY ["./scripts/", "/work/scripts/"]
ENV BUILD_SCRIPTS=/work/scripts
RUN chmod +x $BUILD_SCRIPTS/*.sh && \
    ls -al $BUILD_SCRIPTS && \
    cp $BUILD_SCRIPTS/run.sh /run.sh && \
    cp $BUILD_SCRIPTS/overlay-init.sh $ROOTFS_PATH/overlay-init.sh && \
    mkdir -p $ROOTFS_PATH/boot/EFI && \
    mkdir -p $ROOTFS_PATH/etc/init && \
    cp -rf $BUILD_SCRIPTS/etc_init/* $ROOTFS_PATH/etc/init/ && \
    sed -i -e 's/^GRUB_CMDLINE_LINUX=.*$/GRUB_CMDLINE_LINUX="init=\/overlay-init.sh console=tty1"/g' $ROOTFS_PATH/etc/default/grub && \
    cp $BUILD_SCRIPTS/load-no-cloud.sh $ROOTFS_PATH/usr/sbin/load-no-cloud.sh

RUN rm $ROOTFS_PATH/etc/machine-id

RUN mksquashfs $ROOTFS_PATH /work/rootfs.sqfs -b 128K -comp gzip

VOLUME /work/out

CMD /run.sh


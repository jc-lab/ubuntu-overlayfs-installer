FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && \
    apt-get install -y ca-certificates curl

RUN APT_REPO_LIST=$(curl http://mirrors.ubuntu.com/mirrors.txt | grep -v misakamikoto) && \
    APT_REPO=$(echo "$APT_REPO_LIST" | grep kakao | head -n 1) && \
    TEST_A=$(echo $APT_REPO) && \
    if [ "x$TEST_A" == "x" ]; then APT_REPO=$(echo "$APT_REPO_LIST" | head -n 1); fi && \
    echo $APT_REPO > /tmp/apt.repo.txt && \
    echo "\n\
deb $APT_REPO focal main restricted universe multiverse\n\
deb $APT_REPO focal-updates main restricted universe multiverse\n\
deb $APT_REPO focal-backports main restricted universe multiverse\n\
deb $APT_REPO focal-security main restricted universe multiverse\n\
" > /etc/apt/sources.list && \
    apt-get update -y && \
    apt-get install -y xz-utils unzip dump squashfs-tools dosfstools debootstrap whois

ENV ROOTFS_PATH=/work/rootfs

RUN mkdir -p $ROOTFS_PATH && \
    APT_REPO=$(cat /tmp/apt.repo.txt) && \
    debootstrap --arch amd64 focal $ROOTFS_PATH $APT_REPO && \
    cp -f /etc/apt/sources.list $ROOTFS_PATH/etc/apt/sources.list

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
    sed -i -e 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*$/GRUB_CMDLINE_LINUX_DEFAULT="nomodeset"/g' $ROOTFS_PATH/etc/default/grub && \
    sed -i -e 's/^quiet_boot="1"/quiet_boot="0"/g' $ROOTFS_PATH/etc/grub.d/10_linux && \
    cp $BUILD_SCRIPTS/load-no-cloud.sh $ROOTFS_PATH/usr/sbin/load-no-cloud.sh

RUN rm $ROOTFS_PATH/etc/machine-id && \
    rm $ROOTFS_PATH/var/lib/dbus/machine-id

RUN mksquashfs $ROOTFS_PATH /work/rootfs.sqfs -b 128K -comp gzip

VOLUME /work/out

CMD /run.sh


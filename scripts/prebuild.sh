#!/bin/bash

set -e -x

export DEBIAN_FRONTEND=noninteractive

KUBERNETES_VERSION=1.18.8-00

debconf-set-selections <<< "grub-efi-amd64 grub2/update_nvram boolean false"
apt-get -y update
apt-get -y install sudo openssh-server containerd apt-transport-https curl gnupg2 grub-efi efibootmgr grub-efi-amd64 grub-efi-amd64-signed shim-signed linux-image-generic linux-firmware cloud-init vim lsof sysstat net-tools cryptsetup cryptsetup-bin mdadm libcryptsetup12 cryptmount

cat >>/etc/modules <<EOF
br_netfilter
nfs
EOF

cat > /etc/sysctl.d/11-k8s-network.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

# INSTALL KUBERNETES

curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -

echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list

apt-get -y update

apt-get install -y kubeadm=$KUBERNETES_VERSION kubelet=$KUBERNETES_VERSION kubectl=$KUBERNETES_VERSION

sed -i -e 's/update_initramfs=yes/update_initramfs=no/g' /etc/initramfs-tools/update-initramfs.conf

apt-mark hold kubeadm kubelet kubectl

systemctl enable cloud-init-local.service
systemctl enable cloud-init.service
systemctl enable systemd-networkd.service


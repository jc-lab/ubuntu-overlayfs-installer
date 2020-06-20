#!/bin/bash

mkdir -p /var/lib/cloud/seed/nocloud-net/

if [ ! -f /var/lib/cloud/seed/nocloud-net/user-data ]; then
  cp /boot/cloud/user-data /var/lib/cloud/seed/nocloud-net/user-data
  chmod 400 /var/lib/cloud/seed/nocloud-net/user-data
fi

if [ ! -f /var/lib/cloud/seed/nocloud-net/meta-data ]; then
  cp /boot/cloud/meta-data /var/lib/cloud/seed/nocloud-net/meta-data
fi



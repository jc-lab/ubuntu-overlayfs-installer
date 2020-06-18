#!/bin/bash

rm -rf /work/out/rootfs.sqfs
dd if=/work/rootfs.sqfs of=/work/out/rootfs.sqfs bs=131072 status=progress

#!/bin/sh
CHROOT=./chroot
./configure-for-rootfs.sh
mksquashfs $CHROOT rootfs.squashfs -all-root -noappend

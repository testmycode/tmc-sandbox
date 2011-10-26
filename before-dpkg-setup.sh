#!/bin/sh
# Enough to make dpkg configurations work
CHROOT=./chroot
mount -t proc proc $CHROOT/proc
mknod $CHROOT/dev/null c 1 3
chmod 666 $CHROOT/dev/null
mkdir -p $CHROOT/var/lib/x11

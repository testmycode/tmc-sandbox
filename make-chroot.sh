#!/bin/sh
CHROOT=./chroot
mkdir -p $CHROOT
multistrap -f multistrap.conf
umount $CHROOT/proc
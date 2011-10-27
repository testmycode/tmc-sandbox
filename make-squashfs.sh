#!/bin/sh
CHROOT=./chroot
./configure-for-rootfs.sh
DEBUG_OPTS="-noD -noI -noF"
CMD="mksquashfs $CHROOT rootfs.squashfs -all-root -noappend"
if [ -n "$UNCOMPRESSED_SQUASHFS" ]; then
  CMD="$CMD $DEBUG_OPTS"
fi
$CMD

#!/bin/sh
# This is called by multistrap after extracting all debs and before configuring them.
CHROOT=./output/chroot

# The setups of some Java packages expect proc to be mounted.
mount -t proc proc $CHROOT/proc

# /dev/null is such a popular redirect target that we'll want to make sure it's available
if [ ! -e $CHROOT/dev/null ]; then
  mknod $CHROOT/dev/null c 1 3
  chmod 666 $CHROOT/dev/null
fi

# The JRE package setup fails if this directory is missing
mkdir -p $CHROOT/var/lib/x11


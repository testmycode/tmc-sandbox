#!/bin/sh -e
KERNEL_DIR=$1
SUBMAKE_JOBS=$2

cd $KERNEL_DIR
if [ ! -d fs/aufs ]; then
  patch -p1 < ../aufs3-standalone/aufs3-kbuild.patch
  patch -p1 < ../aufs3-standalone/aufs3-base.patch
  patch -p1 < ../aufs3-standalone/aufs3-proc_map.patch
  cp -av ../aufs3-standalone/Documentation/* Documentation/
  cp -av ../aufs3-standalone/fs/* fs/
  cp -av ../aufs3-standalone/include/linux/aufs_type.h include/linux/
  cp -av ../aufs3-standalone/include/uapi/linux/aufs_type.h include/uapi/linux/
fi

if [ `uname -i` = i386 ]; then
    # Our default config is for amd64
    make oldnoconfig ARCH=um
fi

make -j$SUBMAKE_JOBS ARCH=um


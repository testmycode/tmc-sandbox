#!/bin/sh -e
KERNEL_DIR=$1
SUBMAKE_JOBS=$2

cd $KERNEL_DIR
patch -p1 < ../aufs3-standalone/aufs3-kbuild.patch
patch -p1 < ../aufs3-standalone/aufs3-base.patch
patch -p1 < ../aufs3-standalone/aufs3-proc_map.patch
patch -p1 < ../aufs3-standalone/aufs3-standalone.patch
patch -p1 < ../../kernel/fpu-fix.patch
cp -av ../aufs3-standalone/Documentation/* Documentation/
cp -av ../aufs3-standalone/fs/* fs/
cp -av ../aufs3-standalone/include/linux/aufs_type.h include/linux/
cp -v ../../kernel/kernel-config ./.config
make -j$SUBMAKE_JOBS ARCH=um


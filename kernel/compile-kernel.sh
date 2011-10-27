#!/bin/sh
cd `dirname "$0"`
VERSION=3.0.4

if [ ! -e linux-$VERSION.tar.bz2 ]; then
  wget http://www.kernel.org/pub/linux/kernel/v3.0/linux-$VERSION.tar.bz2
fi

if [ ! -d aufs3-standalone ]; then
  git clone -b aufs3.0 git://aufs.git.sourceforge.net/gitroot/aufs/aufs3-standalone.git aufs3-standalone
fi

if [ ! -d linux-$VERSION ]; then
  tar xvjf linux-$VERSION.tar.bz2
  cd linux-$VERSION
  patch -p1 < ../aufs3-standalone/aufs3-kbuild.patch
  patch -p1 < ../aufs3-standalone/aufs3-base.patch
  patch -p1 < ../aufs3-standalone/aufs3-proc_map.patch
  patch -p1 < ../aufs3-standalone/aufs3-standalone.patch
  cp -av ../aufs3-standalone/Documentation/* Documentation/
  cp -av ../aufs3-standalone/fs/* fs/
  cp -av ../aufs3-standalone/include/linux/aufs_type.h include/linux/
  cp -v ../kernel-config ./.config
  make -j3 ARCH=um
  cd -
else
  echo
  echo "Kernel already compiled."
  echo "Remove linux-$VERSION to recompile."
  echo
fi

ln -f linux-$VERSION/linux linux.uml

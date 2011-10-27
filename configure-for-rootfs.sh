#!/bin/sh
# Adapted from http://fs.devloop.org.uk/filesystems/Debian-Squeeze/log.amd64

CHROOT=./chroot
KERNEL_VERSION=2.6.32

# Ensure the kernel is compiled (TODO: this script needs to be renamed)
kernel/compile-kernel.sh
cp -f kernel/linux.uml ./linux.uml

# Create initrd
./make-initrd.sh

# /sbin/tmc-init
cp tmc-init/tmc-init $CHROOT/sbin/tmc-init
chmod +x $CHROOT/sbin/tmc-init

#TODO: won't need the stuff below any more. remove when refactoring
# fstab
cat > $CHROOT/etc/fstab <<END
none            /proc           proc    defaults                0   0
tmpfs           /tmp            tmpfs   defaults,size=32M       0   0
END

# network-related
echo "127.0.0.1 localhost" > $CHROOT/etc/hosts
echo "tmc-sandbox" > $CHROOT/etc/hostname
echo 'UML_SWITCH_START="false"' > $CHROOT/etc/default/uml-utilities

# inittab
if [ ! -f $CHROOT/etc/inittab.dist ]; then
  cp $CHROOT/etc/inittab $CHROOT/etc/inittab.dist
else
  cp $CHROOT/etc/inittab.dist $CHROOT/etc/inittab
fi
sed -i -e 's/id:2:initdefault:/id:1:initdefault:/' $CHROOT/etc/inittab
sed -i -e 's/\(.*getty\)/#\1/g' $CHROOT/etc/inittab
echo "# For virtualized environments" >> $CHROOT/etc/inittab
echo "c0:12345:respawn:/sbin/getty 38400 tty0 linux" >> $CHROOT/etc/inittab

# securetty
if [ ! -f $CHROOT/etc/securetty.dist ]; then
  cp $CHROOT/etc/securetty $CHROOT/etc/securetty.dist
else
  cp $CHROOT/etc/securetty.dist $CHROOT/etc/securetty
fi
echo "# For virtualized environments" >> $CHROOT/etc/securetty
echo "tty0" >> $CHROOT/etc/securetty
echo "vc/0" >> $CHROOT/etc/securetty

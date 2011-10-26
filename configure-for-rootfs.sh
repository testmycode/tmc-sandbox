#!/bin/sh
# Adapted from http://fs.devloop.org.uk/filesystems/Debian-Squeeze/log.amd64

CHROOT=./chroot

# fstab
cat > $CHROOT/etc/fstab <<END
none            /proc           proc    defaults                0   0
tmpfs           /tmp            tmpfs   defaults,size=32M       0   0
END

# network-related
echo "127.0.0.1 localhost" > $CHROOT/etc/hosts
echo "tmc-sandbox" > $CHROOT/etc/hostname

# inittab
if [ ! -f $CHROOT/etc/inittab.dist ]; then
  cp $CHROOT/etc/inittab $CHROOT/etc/inittab.dist
else
  cp $CHROOT/etc/inittab.dist $CHROOT/etc/inittab
fi
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



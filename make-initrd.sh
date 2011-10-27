#!/bin/sh
# Creates a minimal initrd that uses aufs to layer a ramdisk on the read-only squashfs rootfs
# Useful tutorials:
# http://wiki.sourcemage.org/HowTo/Initramfs#Structure_of_an_initramfs
# http://cianer.com/linux/81-read-only-root-partition-with-aufs

CHROOT=../chroot
KERNEL_VERSION=2.6.32
BUSYBOX_VERSION=1.19.2

mkdir -p initrd
cd initrd

# Download busybox if not downloaded yet
if [ ! -f busybox-$BUSYBOX_VERSION.tar.bz2 ]; then
  echo "Downloading busybox..."
  wget http://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2
fi

# Compile busybox if not compiled yet
if [ ! -f busybox-$BUSYBOX_VERSION/_install/bin/busybox ]; then
  echo "Compiling busybox..."
  tar xvjf busybox-$BUSYBOX_VERSION.tar.bz2
  cp ../busybox-config busybox-$BUSYBOX_VERSION/.config
  make -C busybox-$BUSYBOX_VERSION
  make -C busybox-$BUSYBOX_VERSION install
fi

echo "Creating initrd..."

# Create target directory
rm -Rf target
mkdir target

# Busybox and its command aliases
cp -a busybox-$BUSYBOX_VERSION/_install/* target/

# Kernel modules
mkdir -p target/lib/modules
cp -a $CHROOT/usr/lib/uml/modules/$KERNEL_VERSION target/lib/modules/$KERNEL_VERSION

# Static device files
cp -a $CHROOT/dev target/dev

# The init script
cat > target/init <<END
#!/bin/busybox ash
echo "TMC customized initrd starting"
[ -e /dev/ubda ] || mknod /dev/ubda b 98 0

mkdir /ro
mkdir /rw
mount -t squashfs -o ro /dev/ubda /ro
mount -t tmpfs -o rw,size=64M none /rw

modprobe aufs
mkdir /aufs
mount -t aufs -o rw,br=/rw:/ro aufs /aufs

exec switch_root /aufs /sbin/tmc-init
END

chmod +x target/init

# Package the initrd
rm -f ../initrd.img
cd target
mkdir -p proc sys tmp var
find . | cpio --quiet -H newc -o | gzip > ../../initrd.img
cd ..

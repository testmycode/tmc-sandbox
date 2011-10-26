
This is a work in progress.

1. sudo ./make-chroot.sh             (will call `before-dpkg-setup.sh` internally)
2. sudo ./configure-for-rootfs.sh    (idempotent, will call `make-initrd.sh` internally)
3. sudo ./make-squashfs.sh           (idempotent)


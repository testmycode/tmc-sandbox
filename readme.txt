
1. sudo ./make-chroot.sh             (will call before-dpkg-setup.sh internally)
2. sudo ./configure-for-rootfs.sh    (idempotent)
3. sudo ./make-squashfs.sh           (idempotent)


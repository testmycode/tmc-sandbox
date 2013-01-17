
# Let's not allow parallel operation if for no other reason than to avoid mangled output
# Set SUBMAKE_JOBS to pass -jN to submakes. Defaults to 3.
.NOTPARALLEL:

ifeq ($(SUBMAKE_JOBS),)
  SUBMAKE_JOBS=3
endif

ifneq ("$(shell id -nu)","root")
  $(error Makefile must be run as root)
endif

ARCH := $(shell dpkg --print-architecture)

all: kernel initrd rootfs

# Output directory
OUT=output
CHROOT=$(OUT)/chroot

dummy_create_output_dir := $(shell test -d $(OUT) || mkdir -p $(OUT))

# Version numbers
KERNEL_VERSION=3.4.1
KERNEL_AUFS_BRANCH=aufs3.4
MAVEN_VERSION=3.0.4

kernel: $(OUT)/linux.uml

$(OUT)/linux.uml: $(OUT)/linux-$(KERNEL_VERSION) $(OUT)/aufs3-standalone
	build-scripts/compile-kernel.sh $(OUT)/linux-$(KERNEL_VERSION) $(SUBMAKE_JOBS)
	cp -f $(OUT)/linux-$(KERNEL_VERSION)/linux $@

$(OUT)/linux-$(KERNEL_VERSION): $(OUT)/linux-$(KERNEL_VERSION).tar.bz2
	tar -C $(OUT) -xvjf $(OUT)/linux-$(KERNEL_VERSION).tar.bz2
	cp kernel/kernel-config.amd64 $(OUT)/linux-$(KERNEL_VERSION)/.config

$(OUT)/linux-$(KERNEL_VERSION).tar.bz2:
	wget -O $@ http://www.kernel.org/pub/linux/kernel/v3.0/linux-$(KERNEL_VERSION).tar.bz2

$(OUT)/aufs3-standalone:
	git clone -b $(KERNEL_AUFS_BRANCH) git://aufs.git.sourceforge.net/gitroot/aufs/aufs3-standalone.git $(OUT)/aufs3-standalone


# Chroot and rootfs
rootfs: $(OUT)/rootfs.squashfs

ifneq ($(NO_SQUASHFS_COMPRESS),)
  SQUASHFS_EXTRA_OPTS="-noD -noI -noF"
endif

$(OUT)/rootfs.squashfs: chroot
	mksquashfs $(CHROOT) $@ -all-root -noappend -e var/cache/apt $(SQUASHFS_EXTRA_OPTS)
	chmod a+r $@

chroot: $(CHROOT)/var/log/dpkg.log $(CHROOT)/sbin/tmc-init $(CHROOT)/sbin/fast-shutdown maven

$(OUT)/multistrap.conf: rootfs/multistrap.conf.in
	sed 's/__ARCH__/$(ARCH)/' < $< > $@

$(CHROOT)/var/log/dpkg.log: $(OUT)/multistrap.conf
	mkdir -p $(CHROOT)
	multistrap -f $(OUT)/multistrap.conf
	echo "en_US.UTF-8 UTF-8" > $(CHROOT)/etc/locale.gen
	chroot $(CHROOT) /usr/sbin/locale-gen
	umount $(CHROOT)/proc

$(CHROOT)/sbin/tmc-init: $(CHROOT)/var/log/dpkg.log rootfs/tmc-init
	cp rootfs/tmc-init $(CHROOT)/sbin/tmc-init
	chmod +x $(CHROOT)/sbin/tmc-init

$(CHROOT)/sbin/fast-shutdown: rootfs/fast-shutdown.c
	gcc -Os -o $@ $<

# Maven
maven: $(CHROOT)/usr/local/bin/mvn $(CHROOT)/opt/maven $(CHROOT)/etc/maven-settings.template.xml

$(CHROOT)/usr/local/bin/mvn: $(CHROOT)/opt/apache-maven-$(MAVEN_VERSION)/bin/mvn
	rm -f $@
	mkdir -p $(CHROOT)/usr/local/bin
	cd $(CHROOT)/usr/local/bin && ln -sf /opt/apache-maven-$(MAVEN_VERSION)/bin/mvn

$(CHROOT)/opt/apache-maven-$(MAVEN_VERSION)/bin/mvn: $(OUT)/apache-maven-$(MAVEN_VERSION)-bin.tar.gz
	tar -C $(CHROOT)/opt -xvzf $<
	touch $@ # Update timestamp for make

$(OUT)/apache-maven-$(MAVEN_VERSION)-bin.tar.gz:
	wget -O $@ http://www.nic.funet.fi/pub/mirrors/apache.org/maven/maven-3/$(MAVEN_VERSION)/binaries/apache-maven-$(MAVEN_VERSION)-bin.tar.gz

$(CHROOT)/opt/maven: $(CHROOT)/opt/apache-maven-$(MAVEN_VERSION)
	rm -f $@
	cd $(CHROOT)/opt && ln -s apache-maven-$(MAVEN_VERSION) maven

$(CHROOT)/etc/maven-settings.template.xml: rootfs/maven-settings.template.xml
	cp -f $< $@

# Busybox
BUSYBOX_VERSION=1.20.1
BUSYBOX_INSTALL_DIR=$(OUT)/busybox-$(BUSYBOX_VERSION)/_install
busybox: $(BUSYBOX_INSTALL_DIR)/bin/busybox

$(BUSYBOX_INSTALL_DIR)/bin/busybox: $(OUT)/busybox-$(BUSYBOX_VERSION) busybox/busybox-config
	cp busybox/busybox-config $(OUT)/busybox-$(BUSYBOX_VERSION)/.config
	make -C $(OUT)/busybox-$(BUSYBOX_VERSION) -j$(SUBMAKE_JOBS)
	make -C $(OUT)/busybox-$(BUSYBOX_VERSION) install

$(OUT)/busybox-$(BUSYBOX_VERSION): $(OUT)/busybox-$(BUSYBOX_VERSION).tar.bz2
	tar -C $(OUT) -xvjf $(OUT)/busybox-$(BUSYBOX_VERSION).tar.bz2

$(OUT)/busybox-$(BUSYBOX_VERSION).tar.bz2:
	wget -O $@ http://busybox.net/downloads/busybox-$(BUSYBOX_VERSION).tar.bz2

# Initrd
initrd: $(OUT)/initrd.img

$(OUT)/initrd.img: $(OUT)/initrd/init
	cd $(OUT)/initrd && mkdir -p proc sys tmp var
	cd $(OUT)/initrd && find . | cpio --quiet -H newc -o | gzip > ../initrd.img

$(OUT)/initrd/init: chroot busybox
	mkdir -p $(OUT)/initrd
	cp -a $(BUSYBOX_INSTALL_DIR)/* $(OUT)/initrd/
	cp -a $(CHROOT)/dev $(OUT)/initrd/dev
	cp initrd/initrd-init-script $(OUT)/initrd/init
	chmod +x $(OUT)/initrd/init

# Cleanup
clean: clean-kernel clean-rootfs clean-busybox clean-initrd
	

distclean:
	rm -Rf $(OUT)

clean-kernel:
	rm -Rf $(OUT)/linux-$(KERNEL_VERSION)
	rm -Rf $(OUT)/linux-$(KERNEL_VERSION).tar.bz2
	rm -Rf $(OUT)/aufs3-standalone

distclean-kernel: clean-kernel
	rm -Rf $(OUT)/linux.uml

clean-rootfs:
	rm -Rf $(CHROOT)
	rm -Rf $(OUT)/multistrap.conf

distclean-rootfs: clean-rootfs
	rm -f $(OUT)/rootfs.squashfs

clean-busybox:
	rm -Rf $(OUT)/busybox-$(BUSYBOX_VERSION)
	rm -Rf $(OUT)/busybox-$(BUSYBOX_VERSION).tar.bz2

distclean-busybox: clean-busybox

clean-initrd:
	rm -Rf $(OUT)/initrd

distclean-initrd: clean-initrd
	$(OUT)/initrd.img



# Let's not allow parallel operation if for no other reason than to avoid mangled output
# Set SUBMAKE_JOBS to pass -jN to submakes.
.NOTPARALLEL:

ifeq ($(SUBMAKE_JOBS),)
  SUBMAKE_JOBS=6
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
KERNEL_VERSION=4.9.57
KERNEL_AUFS_BRANCH=aufs4.9
KERNEL_AUFS_COMMIT=5b18dc78e44e6123f62a31b6ad20f9cea9cd1242
BUSYBOX_VERSION=1.26.2
MAVEN_VERSION=3.1.1
JDK_VERSION=1.8.0_102
JDK_PACKAGE_VERSION=8u102
RUBY_VERSION=2.4.1

# Kernel
kernel: $(OUT)/linux.uml

$(OUT)/linux.uml: $(OUT)/linux-$(KERNEL_VERSION) $(OUT)/aufs4-standalone
	build-scripts/compile-kernel.sh $(OUT)/linux-$(KERNEL_VERSION) $(SUBMAKE_JOBS)
	cp -f $(OUT)/linux-$(KERNEL_VERSION)/linux $@

$(OUT)/linux-$(KERNEL_VERSION): $(OUT)/linux-$(KERNEL_VERSION).tar.xz
	tar -C $(OUT) -xvJf $(OUT)/linux-$(KERNEL_VERSION).tar.xz
	cp kernel/kernel-config.amd64 $(OUT)/linux-$(KERNEL_VERSION)/.config

$(OUT)/linux-$(KERNEL_VERSION).tar.xz:
	wget -O $@ https://www.kernel.org/pub/linux/kernel/v4.x/linux-$(KERNEL_VERSION).tar.xz || (rm -f $@ && exit 1)

$(OUT)/aufs4-standalone:
	git clone -b $(KERNEL_AUFS_BRANCH) git://github.com/sfjro/aufs4-standalone.git $(OUT)/aufs4-standalone
	cd $(OUT)/aufs4-standalone && git checkout $(KERNEL_AUFS_COMMIT)

# Chroot and rootfs
rootfs: $(OUT)/rootfs.squashfs

ifneq ($(NO_SQUASHFS_COMPRESS),)
  SQUASHFS_EXTRA_OPTS="-noD -noI -noF"
endif

$(OUT)/rootfs.squashfs: chroot
	mksquashfs $(CHROOT) $@ -all-root -noappend -e var/cache/apt $(SQUASHFS_EXTRA_OPTS)
	chmod a+r $@


CHROOT_BASE_TIMESTAMP_FILE=$(CHROOT)/var/log/dpkg.log

chroot: $(CHROOT_BASE_TIMESTAMP_FILE) $(CHROOT)/sbin/tmc-init $(CHROOT)/sbin/fast-shutdown maven ruby tmc-check r-plugin

$(OUT)/multistrap.conf: rootfs/multistrap.conf.in
	sed 's/__ARCH__/$(ARCH)/' < $< > $@

$(CHROOT_BASE_TIMESTAMP_FILE): $(OUT)/multistrap.conf
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

# Java
ifeq ($(ARCH),i386)
  JDK_ARCH=i586
else
  JDK_ARCH=x64
endif
JDK_PACKAGE_FILE=jdk-$(JDK_PACKAGE_VERSION)-linux-$(JDK_ARCH).tar.gz
JDK_URL=http://testmycode.net/sandbox-jdk/$(JDK_PACKAGE_FILE)

java: $(CHROOT)/opt/jdk $(CHROOT)/etc/profile.d/jdk.sh

$(CHROOT)/opt/jdk: $(OUT)/$(JDK_PACKAGE_FILE)
	rm -Rf $@
	mkdir -p $(CHROOT)/opt
	tar -C $(CHROOT)/opt -xvzf $<
	cd $(CHROOT)/opt && ln -sf jdk$(JDK_VERSION) jdk
	touch $@

$(CHROOT)/etc/profile.d/jdk.sh: $(CHROOT_BASE_TIMESTAMP_FILE)
	mkdir -p $(CHROOT)/etc/profile.d
	echo "export JAVA_HOME=/opt/jdk" > $@
	echo "export PATH=\$$JAVA_HOME/bin:\$$PATH" >> $@

$(OUT)/$(JDK_PACKAGE_FILE):
	wget -O $@ $(JDK_URL) || (rm -f $@ && exit 1)

# Maven
maven: $(CHROOT)/usr/local/bin/mvn $(CHROOT)/opt/maven $(CHROOT)/etc/maven-settings.template.xml

$(CHROOT)/usr/local/bin/mvn: $(CHROOT)/opt/apache-maven-$(MAVEN_VERSION)/bin/mvn
	rm -f $@
	cd $(CHROOT)/usr/local/bin && ln -sf /opt/apache-maven-$(MAVEN_VERSION)/bin/mvn

$(CHROOT)/opt/apache-maven-$(MAVEN_VERSION)/bin/mvn: $(OUT)/apache-maven-$(MAVEN_VERSION)-bin.tar.gz
	tar -C $(CHROOT)/opt -xvzf $<
	touch $@ # Update timestamp for make

$(OUT)/apache-maven-$(MAVEN_VERSION)-bin.tar.gz:
	wget -O $@ http://www.nic.funet.fi/pub/mirrors/apache.org/maven/maven-3/$(MAVEN_VERSION)/binaries/apache-maven-$(MAVEN_VERSION)-bin.tar.gz || (rm -f $@ && exit 1)

$(CHROOT)/opt/maven: $(CHROOT)/opt/apache-maven-$(MAVEN_VERSION)
	rm -f $@
	cd $(CHROOT)/opt && ln -s apache-maven-$(MAVEN_VERSION) maven

$(CHROOT)/etc/maven-settings.template.xml: rootfs/maven-settings.template.xml
	cp -f $< $@

# Ruby
ruby: rubygems

RUBYGEMS_TIMESTAMP_FILE=$(CHROOT)/usr/lib/ruby/.gems_installed

rubygems: $(RUBYGEMS_TIMESTAMP_FILE)

$(RUBYGEMS_TIMESTAMP_FILE): $(CHROOT)/usr/bin/ruby
	cp -f /etc/resolv.conf $(CHROOT)/etc/resolv.conf
	chroot $(CHROOT) sh -c "env HOME=/root gem update --system --force"
	chroot $(CHROOT) sh -c "env HOME=/root gem install rspec bundler --force --no-ri --no-rdoc"
	rm -Rf $(CHROOT)/usr/lib/ruby/gems/*/cache
	rm -f $(CHROOT)/etc/resolv.conf  # tmc-init will create one in the real sandbox
	touch $(RUBYGEMS_TIMESTAMP_FILE)


$(CHROOT)/usr/bin/ruby: $(OUT)/ruby-$(RUBY_VERSION).tar.bz2 $(CHROOT_BASE_TIMESTAMP_FILE)
	rm -Rf $(CHROOT)/root/ruby-$(RUBY_VERSION)
	tar -C $(CHROOT)/root -xvjf $<
	chroot $(CHROOT) sh -c "cd /root/ruby-$(RUBY_VERSION) && ./configure --disable-install-doc --prefix=/usr && make -j$(SUBMAKE_JOBS) && make install"
	rm -Rf $(CHROOT)/root/ruby-$(RUBY_VERSION)

$(OUT)/ruby-$(RUBY_VERSION).tar.bz2:
	wget -O $@ ftp://ftp.ruby-lang.org/pub/ruby/2.4/ruby-$(RUBY_VERSION).tar.bz2 || (rm -f $@ && exit 1)

# TMC Check
tmc-check: $(CHROOT)/usr/lib/pkgconfig/tmccheck.pc

$(CHROOT)/usr/lib/pkgconfig/tmccheck.pc: $(OUT)/tmc-check $(CHROOT_BASE_TIMESTAMP_FILE)
	rm -Rf $(CHROOT)/root/tmc-check
	cp -r $(OUT)/tmc-check $(CHROOT)/root/tmc-check
	cp -f /etc/resolv.conf $(CHROOT)/etc/resolv.conf  # For bundle install to work
	chroot $(CHROOT) sh -c "cd /root/tmc-check && make && make install PREFIX=/usr"
	rm -f $(CHROOT)/etc/resolv.conf  # tmc-init will create one in the real sandbox
	rm -Rf $(CHROOT)/root/tmc-check

$(OUT)/tmc-check:
	cd $(OUT) && git clone https://github.com/testmycode/tmc-check.git


# Busybox
BUSYBOX_INSTALL_DIR=$(OUT)/busybox-$(BUSYBOX_VERSION)/_install
busybox: $(BUSYBOX_INSTALL_DIR)/bin/busybox

$(BUSYBOX_INSTALL_DIR)/bin/busybox: $(OUT)/busybox-$(BUSYBOX_VERSION) busybox/busybox-config
	cp busybox/busybox-config $(OUT)/busybox-$(BUSYBOX_VERSION)/.config
	make -C $(OUT)/busybox-$(BUSYBOX_VERSION) -j$(SUBMAKE_JOBS)
	make -C $(OUT)/busybox-$(BUSYBOX_VERSION) install

$(OUT)/busybox-$(BUSYBOX_VERSION): $(OUT)/busybox-$(BUSYBOX_VERSION).tar.bz2
	tar -C $(OUT) -xvjf $(OUT)/busybox-$(BUSYBOX_VERSION).tar.bz2

$(OUT)/busybox-$(BUSYBOX_VERSION).tar.bz2:
	wget -O $@ http://busybox.net/downloads/busybox-$(BUSYBOX_VERSION).tar.bz2 || (rm -f $@ && exit 1)

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

# R-plugin
r-plugin:
	cp /etc/resolv.conf $(CHROOT)/etc/resolv.conf
	chroot $(CHROOT) sh -c "env HOME=/root Rscript -e 'install.packages(c(\"devtools\",\"testthat\", \"httr\", \"curl\"),repos=\"http://cran.us.r-project.org\")'"
	chroot $(CHROOT) sh -c "env HOME=/root Rscript -e 'devtools::install_github(\"RTMC/tmc-r-tester/tmcRtestrunner\")'"
	rm $(CHROOT)/etc/resolv.conf

# Cleanup
clean: clean-kernel clean-ruby clean-tmc-check clean-rootfs clean-busybox clean-initrd


distclean:
	rm -Rf $(OUT)

clean-kernel:
	rm -Rf $(OUT)/linux-$(KERNEL_VERSION)
	rm -Rf $(OUT)/linux-$(KERNEL_VERSION).tar.xz
	rm -Rf $(OUT)/aufs4-standalone

distclean-kernel: clean-kernel
	rm -Rf $(OUT)/linux.uml

clean-rootfs:
	rm -Rf $(CHROOT)
	rm -Rf $(OUT)/multistrap.conf

distclean-rootfs: clean-rootfs
	rm -f $(OUT)/rootfs.squashfs

clean-ruby:
	rm -f $(OUT)/ruby-$(RUBY_VERSION).tar.bz2

distclean-ruby: clean-ruby

clean-tmc-check:
	rm -Rf $(OUT)/tmc-check

distclean-tmc-check: clean-tmc-check

clean-busybox:
	rm -Rf $(OUT)/busybox-$(BUSYBOX_VERSION)
	rm -Rf $(OUT)/busybox-$(BUSYBOX_VERSION).tar.bz2

distclean-busybox: clean-busybox

clean-initrd:
	rm -Rf $(OUT)/initrd

distclean-initrd: clean-initrd
	$(OUT)/initrd.img

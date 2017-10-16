
# Let's not allow parallel operation if for no other reason than to avoid mangled output
# Set SUBMAKE_JOBS to pass -jN to submakes. Defaults to 3.
.NOTPARALLEL:
ifeq ($(SUBMAKE_JOBS),)
  SUBMAKE_JOBS=3
endif

WORK=work

dummy_create_work_dir := $(shell test -d $(WORK) || mkdir -p $(WORK))

DNSMASQ_VERSION=2.78
SQUID_VERSION=3.5.26

DNSMASQ_URL=http://www.thekelleys.org.uk/dnsmasq/dnsmasq-$(DNSMASQ_VERSION).tar.gz
SQUID_URL=http://www.squid-cache.org/Versions/v3/3.5/squid-$(SQUID_VERSION).tar.gz

DNSMASQ_DIR=$(WORK)/dnsmasq-$(DNSMASQ_VERSION)
SQUID_DIR=$(WORK)/squid-$(SQUID_VERSION)

SQUIDROOT=$(shell readlink -f .)/squidroot
SQUID_VAR_OWNER=$(shell stat -c '%u' .)
SQUID_VAR_GROUP=$(shell stat -c '%g' .)

all: dnsmasq squid

dnsmasq: $(DNSMASQ_DIR)/src/dnsmasq
	cp -f $< $@

$(DNSMASQ_DIR)/src/dnsmasq: $(DNSMASQ_DIR)/Makefile
	make -C $(DNSMASQ_DIR) -j$(SUBMAKE_JOBS)

$(DNSMASQ_DIR)/Makefile: $(DNSMASQ_DIR).tar.gz
	tar -C $(WORK) -xvf $(DNSMASQ_DIR).tar.gz
	touch $@

$(DNSMASQ_DIR).tar.gz:
	wget $(DNSMASQ_URL) -O $@ || (rm -f $@ && exit 1)


squid: $(SQUIDROOT)/sbin/squid

$(SQUIDROOT)/sbin/squid: $(SQUID_DIR)/src/squid
	make -C $(SQUID_DIR) install
	chown -R $(SQUID_VAR_OWNER) $(SQUIDROOT)/var
	chgrp -R $(SQUID_VAR_GROUP) $(SQUIDROOT)/var

$(SQUID_DIR)/src/squid: $(SQUID_DIR)/Makefile
	make -C $(SQUID_DIR) -j$(SUBMAKE_JOBS)

$(SQUID_DIR)/Makefile: $(SQUID_DIR)/configure
	cd $(SQUID_DIR) && ./configure --prefix $(SQUIDROOT)

$(SQUID_DIR)/configure: $(SQUID_DIR).tar.gz
	tar -C $(WORK) -xvf $<
	touch $@

$(SQUID_DIR).tar.gz:
	wget $(SQUID_URL) -O $@ || (rm -f $@ && exit 1)

clean:
	rm -Rf $(WORK)

distclean: clean
	rm -Rf $(SQUIDROOT) dnsmasq

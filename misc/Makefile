
# Let's not allow parallel operation if for no other reason than to avoid mangled output
# Set SUBMAKE_JOBS to pass -jN to submakes. Defaults to 3.
.NOTPARALLEL:
ifeq ($(SUBMAKE_JOBS),)
  SUBMAKE_JOBS=3
endif

WORK=work

dummy_create_work_dir := $(shell test -d $(WORK) || mkdir -p $(WORK))

DNSMASQ_VERSION=2.62
SQUID_VERSION=3.3.9

DNSMASQ_URL=http://www.thekelleys.org.uk/dnsmasq/dnsmasq-$(DNSMASQ_VERSION).tar.gz
SQUID_URL=http://www.squid-cache.org/Versions/v3/3.3/squid-$(SQUID_VERSION).tar.gz

DNSMASQ_DIR=$(WORK)/dnsmasq-$(DNSMASQ_VERSION)
SQUID_DIR=$(WORK)/squid-$(SQUID_VERSION)

SQUIDROOT=$(shell readlink -f .)/squidroot

all: dnsmasq squid

dnsmasq: $(DNSMASQ_DIR)/src/dnsmasq
	cp -f $< $@

$(DNSMASQ_DIR)/src/dnsmasq: $(DNSMASQ_DIR)/Makefile
	make -C $(DNSMASQ_DIR) -j$(SUBMAKE_JOBS)

$(DNSMASQ_DIR)/Makefile: $(DNSMASQ_DIR).tar.gz
	tar -C $(WORK) -xvf $(DNSMASQ_DIR).tar.gz
	touch $@

$(DNSMASQ_DIR).tar.gz:
	wget -c $(DNSMASQ_URL) -O $@


squid: $(SQUIDROOT)/sbin/squid

$(SQUIDROOT)/sbin/squid: $(SQUID_DIR)/src/squid
	make -C $(SQUID_DIR) install

$(SQUID_DIR)/src/squid: $(SQUID_DIR)/Makefile
	make -C $(SQUID_DIR) -j$(SUBMAKE_JOBS)

$(SQUID_DIR)/Makefile: $(SQUID_DIR)/configure
	cd $(SQUID_DIR) && ./configure --prefix $(SQUIDROOT)

$(SQUID_DIR)/configure: $(SQUID_DIR).tar.gz
	tar -C $(WORK) -xvf $<
	touch $@

$(SQUID_DIR).tar.gz:
	wget -c $(SQUID_URL) -O $@

clean:
	rm -Rf $(WORK)

distclean: clean
	rm -Rf $(SQUIDROOT) dnsmasq

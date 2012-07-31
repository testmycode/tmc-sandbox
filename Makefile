
# Let's not allow parallel operation if for no other reason than to avoid mangled output
# Set SUBMAKE_JOBS to pass -jN to submakes. Defaults to 3.
.NOTPARALLEL:

ifeq ($(SUBMAKE_JOBS),)
  SUBMAKE_JOBS=3
endif

ifneq ("$(shell id -nu)","root")
  $(error Makefile must be run as root)
endif

.PHONY: uml misc clean distclean check

all: uml misc

uml:
	make -C uml

misc:
	make -C misc

clean:
	make -C uml clean
	make -C misc clean

distclean:
	make -C uml distclean
	make -C misc distclean

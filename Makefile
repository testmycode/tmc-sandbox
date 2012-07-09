
# Let's not allow parallel operation if for no other reason than to avoid mangled output
# Set SUBMAKE_JOBS to pass -jN to submakes. Defaults to 3.
.NOTPARALLEL:

ifeq ($(SUBMAKE_JOBS),)
  SUBMAKE_JOBS=3
endif

ifneq ("$(shell id -nu)","root")
  $(error Makefile must be run as root)
endif

.PHONY: uml web clean distclean check

all: uml web

uml:
	make -C uml

web:
	cd web && rake

clean:
	make -C uml clean
	cd web && rake clean

distclean:
	make -C uml distclean
	cd web && rake clean

check:
	echo "Running tests in web/"
	cd web && rake test
	echo "Running tests in management/"
	cd management && rake tests

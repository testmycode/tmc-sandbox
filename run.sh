#!/bin/sh

if [ ! -f test/data/test-exercise ]; then
  cd test/data
  rm -f test-exercise.tar
  tar -C test-exercise -cf test-exercise.tar . || exit 1
  cd -
fi

if [ ! -x test/helpers/remove-trailing-nulls ]; then
  cd test/helpers
  gcc -o remove-trailing-nulls remove-trailing-nulls.c || exit 1
  cd -
fi

MAX_OUTPUT_SIZE=20M
dd if=/dev/zero of=test/output.txt0 bs=$MAX_OUTPUT_SIZE count=1

output/linux.uml \
  initrd=output/initrd.img \
  ubda=output/rootfs.squashfs \
  ubdb=test/data/test-exercise.tar \
  ubdc=test/output.txt0 \
  mem=256M

test/helpers/remove-trailing-nulls < test/output.txt0 > test/output.txt


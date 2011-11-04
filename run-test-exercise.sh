#!/bin/sh

rm -Rf tmp
mkdir -p tmp
tar -C test/data/test-exercise -cf tmp/test-exercise.tar . || exit 1
gcc -o tmp/remove-trailing-nulls test/helpers/remove-trailing-nulls.c || exit 1

MAX_OUTPUT_SIZE=20M
dd if=/dev/zero of=tmp/output.txt0 bs=$MAX_OUTPUT_SIZE count=1

output/linux.uml \
  initrd=output/initrd.img \
  ubda=output/rootfs.squashfs \
  ubdb=tmp/test-exercise.tar \
  ubdc=tmp/output.txt0 \
  mem=128M

tmp/remove-trailing-nulls < tmp/output.txt0 > tmp/output.txt


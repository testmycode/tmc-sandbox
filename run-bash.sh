#!/bin/sh

rm -Rf tmp
mkdir -p tmp
cat > tmp/tmc-run <<EOS
#!/bin/sh
cd /
/bin/bash
EOS
chmod +x tmp/tmc-run

tar -C tmp -cf tmp/bash-runner.tar tmc-run || exit 1

output/linux.uml \
  initrd=output/initrd.img \
  ubda=output/rootfs.squashfs \
  ubdb=tmp/bash-runner.tar \
  mem=128M


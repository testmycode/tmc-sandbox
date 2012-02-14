#!/bin/sh

# Put stuff in test/bash-runner/ (create it first) and it'll be in /tmc/ in the sandbox.

rm -Rf tmp
mkdir -p tmp
cat > tmp/tmc-run <<EOS
#!/bin/sh
echo "ok" > output.txt
EOS
chmod +x tmp/tmc-run
test -d test/bash-runner && cp -r test/bash-runner/* tmp/

cd tmp
tar -cf bash-runner.tar * || exit 1
cd ..

MAX_OUTPUT_SIZE=20M
dd if=/dev/zero of=tmp/output.tar bs=$MAX_OUTPUT_SIZE count=1

output/linux.uml \
  initrd=output/initrd.img \
  ubdarc=output/rootfs.squashfs \
  ubdbr=tmp/bash-runner.tar \
  ubdc=tmp/output.tar \
  mem=96M \
  tmc_run_bash


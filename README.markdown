
The TMC sandbox consists of the following:

- A [User-Mode Linux](http://user-mode-linux.sourceforge.net/) kernel.
- A minimal Linux root disk image with compilers and stuff. Currently based on Debian 6 using [Multistrap](http://wiki.debian.org/Multistrap) but something smaller might be nice.
- An initrd that layers a ramdisk on top of the read-only root disk (using [aufs](http://aufs.sourceforge.net/)).

The sandbox is invoked by starting `linux.uml` with at least the following kernel parameters:

- `initrd=initrd.img` - the initrd.
- `ubda=rootfs.squashfs` - the rootfs.
- `ubdb=runnable.tar` - an uncompressed tar file containing an executable `tmc-run`.
- `ubdc=output.txt0` - a zeroed file with enough space for the output. `output.txt` will be written to the beginning. The rest will be zeroes.
- `mem=xyzM` - the memory limit.

The normal boot process is skipped. The initrd invokes a custom init script that prepares a very minimal environment, calls `tmc-run`, flushes output and directly halts the virtual machine.

Build with `sudo make` and test with `./run.sh`.
You may need to download `http://ftp-master.debian.org/archive-key-6.0.asc` and `apt-key add` if running Ubuntu or similar.


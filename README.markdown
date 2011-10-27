
The TMC sandbox consists of the following:

- A [User-Mode Linux](http://user-mode-linux.sourceforge.net/) kernel.
- A minimal Linux root disk image with compilers and stuff. Currently based on Debian 6 using [Multistrap](http://wiki.debian.org/Multistrap).
- An initrd that layers a ramdisk on top of the read-only root disk (using [aufs](http://aufs.sourceforge.net/)).

`sudo make` to build and `./run.sh` to test.
You may need to download `http://ftp-master.debian.org/archive-key-6.0.asc` and `apt-key add` if running Ubuntu or similar.


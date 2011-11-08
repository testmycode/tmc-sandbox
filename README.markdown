
The TMC sandbox consists of the following:

- A [User-Mode Linux](http://user-mode-linux.sourceforge.net/) kernel.
- A minimal Linux root disk image with compilers and stuff. Currently based on Debian 6 using [Multistrap](http://wiki.debian.org/Multistrap) but something smaller might be nice.
- An initrd that layers a ramdisk on top of the read-only root disk (using [aufs](http://aufs.sourceforge.net/)).
- An optional [rack](http://rack.rubyforge.org/) webservice.

## Compiling and running ##

Build with `sudo make` and test with `./run-test-exercise.sh` or `./run-bash.sh`.

You may need to download `http://ftp-master.debian.org/archive-key-6.0.asc` and `apt-key add` if running Ubuntu or similar.

## Options ##

The sandbox is invoked by starting `linux.uml` with at least the following kernel parameters:

- `initrd=initrd.img` - the initrd.
- `ubda=rootfs.squashfs` - the rootfs.
- `ubdb=runnable.tar` - an uncompressed tar file containing an executable `tmc-run`.
- `ubdc=output.tar` - a zeroed file with a reasonable amount of space for the output. `output.txt` will be written there as a tar-file.
- `mem=xyzM` - the memory limit.

The normal boot process is skipped. The initrd invokes a custom init script that prepares a very minimal environment, calls `tmc-run`, flushes output and halts the virtual machine.

## Webservice ##

There's a simple Rack webservice under `web/`. It implements the following protocol.

`POST /`
Expects multipart formdata with these parameters:

- **file**: task file as plain tar file
- **notify**: URL for notification when done
- **token**: token to post to notification URL

It runs the task in the sandbox and sends a POST request
to the notify URL with the following JSON object:

- **status**: one of 'finished', 'failed', 'timeout'
- **token**: the token given in the request
- **output**: the output.txt of the task, if status = 'finished'

Only one task may run per instance of this webservice.
If it is busy, it responds with a HTTP 500 and a JSON object `{status: 'busy'}`.
Multiple instances should be deployed to separate directories under separate URLs.

Authentication and encryption should be configured into the web server as usual.


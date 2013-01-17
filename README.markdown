The TMC sandbox consists of the following:

- A [User-Mode Linux](http://user-mode-linux.sourceforge.net/) kernel.
- A minimal Linux root disk image with compilers and stuff. Currently based on Debian 6 using [Multistrap](http://wiki.debian.org/Multistrap) but something smaller might be nice.
- An initrd that layers a ramdisk on top of the read-only root disk (using [aufs](http://aufs.sourceforge.net/)).
- An optional [rack](http://rack.rubyforge.org/) webservice.

## Compiling and running ##

Install the following prerequisites:

- `build-essential`
- `squashfs-tools`
- `multistrap`

If you're on a Debian derivative, you may need to install Debian's archive key:

    curl -L http://ftp-master.debian.org/archive-key-6.0.asc | sudo apt-key add -

Now build with `sudo make`. Root access is needed by multistrap since it chroots.

You can test the sandbox with `./run-test-exercise.sh` or `./run-bash.sh` under `uml/`.

## Options ##

The sandbox is invoked by starting `uml/linux.uml` with at least the following kernel parameters:

- `initrd=initrd.img` - the initrd.
- `ubdarc=rootfs.squashfs` - the rootfs (the `rc` meaning read-only shared).
- `ubdbr=runnable.tar` - an uncompressed tar file containing an executable `tmc-run`.
- `ubdc=output.tar` - a zeroed file with a reasonable amount of space for the output. `output.txt` will be written there as a tar-file.
- `mem=xyzM` - the memory limit.

The normal boot process is skipped. The initrd invokes a custom init script that prepares a very minimal environment, calls `tmc-run`, flushes output and halts the virtual machine.

## Webservice ##

There's a simple Rack webservice under `web/`.

The service implements the following protocol.

`POST /tasks.json`
Expects multipart formdata with these parameters:

- **file**: task file as plain tar file
- **notify**: URL for notification when done
- **token**: token to post to notification URL

It runs the task in the sandbox and sends a POST request
to the notify URL with the following JSON object:

- **status**: one of 'finished', 'failed', 'timeout'.
    - 'finished' iff `tmc-run` completed successfully with exit code 0.
    - 'timeout' if `tmc-run` took too long to complete
    - 'failed' in any other case
- **exit_code**: the exit code of `tmc-run`, or null if not applicable
- **token**: the token given in the request
- **test_output**: the test_output.txt created by the task. May be empty.
- **stdout**: the stdout.txt created by the task. May be empty.
- **stderr**: the stderr.txt created by the task. May be empty.

Only a limited number of tasks may run per instance of this webservice.
If it is busy, it responds with a HTTP 500 and a JSON object `{status: 'busy'}`.

### Setup ###

First, read through the configuration file in `site.defaults.yml`.

Install dependencies with `bundle install` and
compile the small C extension with `rake ext`.

Run tests by doing `sudo rake test` under `web/`. It requires `e2fsprogs` and `e2tools` to be installed.

Start the service with `sudo webapp.rb run` and stop it with Ctrl-C.
That script does the extra setup needed for network support, if configured,
and then invokes `rackup` on the configured http port as the configured user account.

The service may be installed as an init script by doing `sudo rake init:install` (or `rvmsudo ...`).

The service should definitely be secured by a firewall or network segregation.

### Network support ###

The web service can be configured to provide very limited network access to the sandboxes.
It uses a TAP device, dnsmasq and squid to give access via a HTTP proxy only.
The required software is included and started/stopped automatically.
Tap devices are also created and configured on demand and destroyed on exit.

### Maven support ###

Running maven projects efficiently is tricky because downloading dependencies
can take a lot of time. We found that a simple HTTP cache outside UML
doesn't help much. For fast execution, the dependencies should already be
in the local repository.

We don't want untrusted code to have write access to the repository.
To solve this, the webservice has an optional plugin
that inspects incoming exercises and starts a background process to
download their dependencies to a cache. This way, a project needs to download
its dependencies in the actual sandbox only on the first run (or the first
few runs if unlucky), when the cache is not yet populated.
The cache may also be populated by a pom.xml file upload to `/maven_cache/populate.json`.

The technical details are documented in `web/plugins/maven_cache.rb`.

The cache must be explicitly enabmed in `site.yml`.

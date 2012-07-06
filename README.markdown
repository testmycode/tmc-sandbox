
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
- `ubdarc=rootfs.squashfs` - the rootfs (the `rc` meaning read-only shared).
- `ubdbr=runnable.tar` - an uncompressed tar file containing an executable `tmc-run`.
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

- **status**: one of 'finished', 'failed', 'timeout'.
    - 'finished' iff `tmc-run` completed successfully with exit code 0.
    - 'timeout' if `tmc-run` took too long to complete
    - 'failed' in any other case
- **exit_code**: the exit code of `tmc-run`, or null if not applicable
- **token**: the token given in the request
- **output**: the output.txt of the task. Empty in some failure cases.

Only one task may run per instance of this webservice.
If it is busy, it responds with a HTTP 500 and a JSON object `{status: 'busy'}`.
Multiple instances should be deployed to separate directories under separate URLs.
They may, however, share the same kernel, initrd and rootfs files.

Authentication and encryption may be configured into the web server if desired.

Tests may be run by doing `rake test` under `web/`. It requires `e2fsprogs` and `e2tools` (i.e. ext2 stuff) to be installed.

There is a setup and administration helper script described below.

## Network setup ##

The suggested network setup uses explicit TAP devices.
One could set up a firewall to route from the TAP device to
the internet, but here we only configure HTTP and DNS proxies to listen
on the TAP device.

There is a script, `management/manage-tap-devices`,
that automates the setup for Debian-based systems.
It is called by the main management script `management/manage-sandboxes`,
but may also be called directly. It's advised you read the following
manual instructions first to understand what the scripts do exactly.

Here is an outline of the network setup:

- On the host:
    - Set up TAP device(s).
    - Connect the sandbox(es) use the TAP device(s).
    - Set up dnsmasq for each TAP device.
    - Set up a [http://www.squid-cache.org/ squid] proxy for each TAP device.
    - Set up the squid proxy's ACL settings.

- In the sandbox:
    - Set up network interface and resolv.conf.
    - Set global proxy settings: `http_proxy` and Java's proxy settings.

Some assumptions, adjust as needed:

- 192.168.88.* is a free local IP range.
- The user account running the sandboxes is `tmc`.

Let's create a TAP interface named `tap_tmc88` and assign it to the 192.168.88.* subnet.

    ip tuntap add dev tap_tmc88 mode tap user tmc
    ifconfig tap_tmc88 192.168.88.1 up

These can be configured above to run on bootup, or with a distro-specific network configuration.
The following is an example for Debian's `/etc/network/interfaces`

    auto tap_tmc88
    iface tap_tmc88 inet static
        address 192.168.88.1
        netmask 255.255.255.0
        pre-up ip tuntap add dev tap_tmc88 mode tap user tmc
        post-down ip tuntap del dev tap_tmc88 mode tap

There is a handy script, `management/manage-tap-devs` for adding or removing
the above in `/etc/network/interfaces`. Run it with `--help` to see.

Now the sandbox's `eth0` can be bound to `tap_tmc88` with the following command line parameter:

    eth0=tuntap,tap_tmc88,,192.168.88.1

If you use the sandbox's web interface then set the following in `site.yml`:

    extra_uml_args: eth0=tuntap,tap_tmc88,,192.168.88.1

If you manage multiple sandboxes then you'll probably want to give each sandbox its own tap device
and subnet. If you use the script under `management/` then this can be done by programming the
configuration object in `config.rb` to return an `extra_uml_args` based on the given port number.

Inside the UML the default tmc-init script will recognize the above command line argument and
do approximately the following setup:

    ifconfig eth0 192.168.88.2 up
    route add -host 192.168.88.2 gw 192.168.88.1
    echo "nameserver 192.168.88.1" > /etc/resolv.conf
    export http_proxy="http://192.168.88.1:3128"
    echo "http.proxyHost=192.168.88.1" >> /etc/java-6-openjdk/net.properties
    echo "http.proxyPort=3128" >> /etc/java-6-openjdk/net.properties

The init script infers the appropriate subnet (here 192.168.88.*) from the CLI option.
It also writes an appropriate `settings.xml` for maven.

Now we could e.g. set up a firewall to forward (limited) traffic from the tun/tap device to the internet.
Instead we'll keep the networks separated and make all communication go through an HTTP proxy. Before
that, however, we'll need to give the sandbox access to DNS.

### dnsmasq ###

Dnsmasq is an easy to set up DNS forwarder and DHCP server. We only want it to
handle DNS requests on our tap device, since since we don't want to route stuff
to the real network. We can configure dnsmasq simply like this:

    interface=tap_tmc88
    no-dhcp-interface=tap_tmc88

These lines may be repeated for all tap devices.
Alternatively an empty configuration will also work but be somewhat
less secure as it will handle all DNS and DHCP from all interfaces.

Note: Ubuntu's NetworkManager (at least in 12.04) has some tie-in with an
unconfigurable copy of dnsmasq. Some trouble may be avoided by uninstalling
NetworkManager before installing the dnsmasq package.

### Squid proxy ###

We assume [http://www.squid-cache.org/ Squid] 3.x is installed.
We'll configure it to listen to the tap interface(s) and forward requests.
Set `http_port` to `192.168.88.1:3128`.
You may repeat this line to support multiple sandboxes.

Look into the `acl` and `http_access` options to configure access limitations.
Some distributions have rather restrictive defaults preconfigured.

You should think about the size of your cache.
The relevant options are `cache_dir` and
`maximum_object_size` for disk cache, and
`cache_mem` and `maximum_object_size_in_memory`
for memory cache.

## Management scripts ##

The above is some heavy configuration and easy to get wrong if done manually.
There is a script `management/manage-sandboxes` that automates creating,
starting, stopping and deleting instances of the sandbox on different ports.
It is configured by a configuration file.

Let's set up a directory for our sandboxes and link the management script to it:

    su tmc  # assume tmc is our server user. Don't run as root.
    mkdir -p $HOME/srv/sandboxes
    cd $HOME/srv/sandboxes
    ln -s /path/to/tmc-sandbox/management/manage-sandboxes

The management script expects a `config.rb` in the working directory
(or specified with `--config`). The default config should usually suffice.

    cp /path/to/tmc-sandbox/management/config.example.rb ./config.rb

Now, a sandbox can be created e.g. on port `3015` by doing

    ./manage-sandboxes create 3015

This creates a copy of the `web/` directory named `3015` and
edits `3015/site.yml` according to `config.rb`.
The sandbox can be started by

    ./manage-sandboxes start 3015

If you change `config.rb`, you must destroy and recreate your sandboxes
to apply the configuration.

Uncomment `include SandboxManager::NetworkConfig` in the config file to get the
default network configuration. By default it assumes sandbox ports are of the
form `30XX`. It uses `management/manage-tap-devs` to configure a tap device
`tap_tmcXX` with an IP `192.168.XX.1` and dnsmasq and squid for it.
It also brings the interface up or down as the sandbox is started and stopped,
and it deletes the interface, the tap device and their configurations when
the sandbox is destroyed.

Note that if you use the network configuration, you must run
the management script as root. In that case it chowns everything it
creates to the `tmc` user and starts sandboxes as that user.

To start sandboxes when the machine boots, add the following line to
the TMC user's crontab.

    @reboot cd $HOME/srv/sandboxes && ./manage-sandboxes onboot

If you have something essential in /usr/local/bin then make that last part

    env PATH=/usr/local/bin:$PATH ./manage-sandboxes onboot


## Maven support ##

Running maven projects efficiently is tricky because downloading dependencies
can take a lot of time. We found that adding a simple web cache outside UML
doesn't help enough. For fast execution, the dependencies should already be
in the local repository. But we don't want untrusted code to have write
access to the repository. To solve this, the webservice has an optional plugin
that inspects incoming exercises and starts a background process to
download their dependencies to a cache. This way, a project needs to download
its dependencies in the actual sandbox only on the first run (or the first
few runs if unlucky), when the cache is not yet populated.

The technical details regarding locking etc are documented
in `web/plugins/maven_cache.rb`.

To use the cache, simply configure it in `site.yml` as instructed there.
You need to set up a network access for it via a dedicated tap device
as described above. If you use the management script then overriding
`enable_maven_cache?` to return true in your `config.rb` is enough.

It's safe and recommended to share the same maven cache images and
TAP device between several sandboxes.



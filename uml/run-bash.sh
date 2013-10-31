#!/bin/sh

# Put stuff in test/bash-runner/ (create it first) and it'll be in /tmc/ in the sandbox.

rm -Rf tmp
mkdir -p tmp
[ `whoami` = root ] && chmod -R a+rwX tmp

if [ "$1" = '-n' ]; then
  NETWORKING=1
  if [ `whoami` != root ]; then
    echo "Run as root to get networking."
    exit 1
  fi
  
  TAPDEV=tap_tmp
  IP=192.168.240.1
  SUBNET=192.168.240.0
  
  NETWORK_OPTS=eth0=tuntap,$TAPDEV,,$IP
  
  MISC_PATH=`dirname "$0"`/../misc
  MISC_PATH=`readlink -f "$MISC_PATH"`
  DNSMASQ_PATH="$MISC_PATH/dnsmasq"
  SQUIDROOT="$MISC_PATH/squidroot"
  SQUID_CONF="$SQUIDROOT/etc/squid.conf"
  SQUID_PATH="$SQUIDROOT/sbin/squid"
  SQUID_USER=`stat -c %U "$SQUIDROOT/var/run"`
  SQUID_PIDFILE="$SQUIDROOT/var/run/squid.pid"
  DNSMASQ_PIDFILE="$SQUIDROOT/var/run/dnsmasq.pid" # borrow squidroot
  
  echo "I'll create a TAP device $TAPDEV with IP $IP."
  echo "Then I'll start the embedded dnsmasq and squid"
  echo "(make sure they're not already running)."
  echo "After the VM exits I'll try to restore everything as it was."
  echo "Hit Ctrl+C now if you don't like this. Press Enter to continue."
  read IGNORE
  
  echo "Creating tap device $TAPDEV with IP $IP"
  ip tuntap add dev $TAPDEV mode tap user root
  ifconfig $TAPDEV $IP netmask 255.255.255.0 up
  
  echo "Configuring squid"
  cat > "$SQUID_CONF" <<EOS
acl SSL_ports port 443
acl Safe_ports port 80          # http
acl Safe_ports port 8080  # alternative http
acl Safe_ports port 443         # https
acl Safe_ports port 1025-65535  # unregistered ports
acl Safe_ports port 280         # http-mgmt
acl Safe_ports port 488         # gss-http
acl Safe_ports port 591         # filemaker
acl Safe_ports port 777         # multiling http
acl CONNECT method CONNECT
acl localnet src $SUBNET/24
http_access allow manager localhost
http_access deny manager
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

http_access deny to_localhost
http_access allow localnet
http_access allow localhost

http_access deny all

http_port 3128

cache_effective_user $SQUID_USER
cache_effective_group nogroup

shutdown_lifetime 2 seconds
EOS

  echo "Starting squid"
  $SQUID_PATH || exit 1
  
  echo "Starting dnsmasq"
  DNSMASQ_OPTS="--conf-file=- --user=$SQUID_USER --group=nogroup --pid-file=$DNSMASQ_PIDFILE --bind-interfaces --interface=$TAPDEV"
  $DNSMASQ_PATH $DNSMASQ_OPTS < /dev/null
  [ $? != 0 ] && (kill `cat $SQUID_PIDFILE` ; exit 1)

else
  NETWORKING=0
fi

mkdir -p tmp/tar
cat > tmp/tar/tmc-run <<EOS
#!/bin/sh
echo "ok" > output.txt
EOS
chmod +x tmp/tar/tmc-run
test -d test/bash-runner && cp -r test/bash-runner/* tmp/tar/

cd tmp/tar
tar -cf ../bash-runner.tar * || exit 1
cd ../..
[ `whoami` = root ] && chmod -R a+rwX tmp


MAX_OUTPUT_SIZE=20M
dd if=/dev/zero of=tmp/output.tar bs=$MAX_OUTPUT_SIZE count=1

MEM=${MEM-256M}

output/linux.uml \
  initrd=output/initrd.img \
  ubdarc=output/rootfs.squashfs \
  ubdbr=tmp/bash-runner.tar \
  ubdc=tmp/output.tar \
  mem=$MEM \
  $NETWORK_OPTS \
  $@ \
  'run:"/bin/bash"'

if [ "$NETWORKING" = 1 ]; then
  echo "Stopping dnsmasq"
  kill `cat $DNSMASQ_PIDFILE`
  
  echo "Stopping squid"
  kill `cat $SQUID_PIDFILE`

  echo "Destroying tap device $TAPDEV"
  ifconfig $TAPDEV down
  ip tuntap del dev $TAPDEV mode tap
fi

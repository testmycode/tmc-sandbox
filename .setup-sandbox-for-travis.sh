#!/bin/bash
# Builds sandbox
curl -L http://ftp-master.debian.org/archive-key-6.0.asc | sudo apt-key add -
# Multistrap is broken so let's fix it - see: https://bugs.launchpad.net/ubuntu/+source/multistrap/+bug/1313787
sudo sed -i -e '989s/$forceyes//' /usr/sbin/multistrap
# To workaround travis timeouts
echo "Builing sandbox, it will take a while (upto 30 minutes)"
#while sleep 1; do echo -n "."; done &
sudo make #> /tmp/build.log 2>&1
#kill %1

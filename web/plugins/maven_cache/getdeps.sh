#!/bin/sh -e

mkdir -p /mnt/rw/maven
ln -s /mnt/rw/maven ~/.m2
if [ -f /mnt/rw/maven/settings.xml ]; then
  cp /mnt/rw/maven/settings.xml ~/.m2/settings.xml
fi

mkdir /tmp/exercise
cd /tmp/exercise
tar xf "$EXERCISE_TAR"
mvn -e dependency:go-offline


#!/bin/sh -e

DEP_PLUGIN_PREFIX=org.apache.maven.plugins:maven-dependency-plugin:2.4

if [ "$1" = "--run-tests" ]; then
  RUN_TESTS=1
fi

mkdir -p /mnt/rw/maven
ln -s /mnt/rw/maven ~/.m2
if [ -f /mnt/rw/maven/settings.xml ]; then
  cp /mnt/rw/maven/settings.xml ~/.m2/settings.xml
fi

mkdir /tmp/exercise
cd /tmp/exercise
tar xf "$EXERCISE_TAR"

if [ "$RUN_TESTS" = "1" ]; then
  mvn -e fi.helsinki.cs.tmc:tmc-maven-plugin:RELEASE:test
else
  mvn -e "$DEP_PLUGIN_PREFIX:go-offline"
  # Ensure we have the latest TMC maven plugin too.
  mvn -Dartifact="fi.helsinki.cs.tmc:tmc-maven-plugin:RELEASE" "$DEP_PLUGIN_PREFIX:get"
fi


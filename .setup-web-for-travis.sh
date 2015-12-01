#!/bin/bash
# Configures and builds web api for travis

cd web/
bundle install  --retry=6 --jobs=3
rake ext
sed -i "s/\(tmc_user: \)tmc/\1 $(whoami)/" site.defaults.yml
sed -i "s/\(tmc_group: \)tmc/\1 $(whoami)/" site.defaults.yml
sed -i 's/\(max_instances: \)[0-9]*/\12/' site.defaults.yml
cd ../



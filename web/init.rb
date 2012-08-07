WEBAPP_ROOT = File.dirname(File.realpath(__FILE__))
$LOAD_PATH.unshift WEBAPP_ROOT + '/ext/misc_utils'
$LOAD_PATH.unshift WEBAPP_ROOT + '/lib'

require 'paths'
require 'settings'
require 'fileutils'
FileUtils.mkdir_p(Paths.lock_dir)
FileUtils.chown(Settings.tmc_user, Settings.tmc_group, Paths.lock_dir)
FileUtils.mkdir_p(Paths.work_dir)
FileUtils.chown(Settings.tmc_user, Settings.tmc_group, Paths.work_dir)
FileUtils.mkdir_p(Paths.log_dir)
FileUtils.chown(Settings.tmc_user, Settings.tmc_group, Paths.log_dir)
FileUtils.touch(Paths.log_dir + 'test.log')
FileUtils.chown(Settings.tmc_user, Settings.tmc_group, Paths.log_dir + 'test.log')

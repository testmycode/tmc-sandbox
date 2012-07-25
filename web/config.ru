# See site.defaults.yml for configuration.

$stdout.reopen("#{File.dirname(File.realpath(__FILE__))}/work/rack.log")
$stderr.reopen($stdout)
$stdout.sync = true
$stderr.sync = true

require 'rack'
require 'rack/commonlogger'
require "#{File.dirname(File.realpath(__FILE__))}/init.rb"
require 'sandbox_app'

log = File.new("#{Paths.work_dir}/access.log", "a+")
log.sync = true
use(Rack::CommonLogger, log)

run SandboxApp.new

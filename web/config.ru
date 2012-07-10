# See site.defaults.yml for configuration.

require "#{File.dirname(File.realpath(__FILE__))}/init.rb"
require 'rack/lock'
require 'sandbox_app'

use Rack::Lock
run SandboxApp.new


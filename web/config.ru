# See site.defaults.yml for configuration.

require "#{File.dirname(File.realpath(__FILE__))}/init.rb"
require 'sandbox_app'

run SandboxApp.new

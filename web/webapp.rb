#!/usr/bin/env ruby
# Entrypoint to the web interface.
# See site.defaults.yml for configuration.

require 'fileutils'
require 'shellwords'

require "#{File.dirname(File.realpath(__FILE__))}/init.rb"
require 'settings'
require 'tap_device'
require 'misc_utils'
require 'dnsmasq'
require 'squid'
require 'process_user'
require 'signal_handlers'
require 'lock_file'
require 'daemons'

class WebappProgram
  def initialize
    @settings = Settings.get
  end

  def run
    raise "This should be run as root." if Process.uid != 0

    mkdir_p_for_tmc_user(Paths.lock_dir)
    mkdir_p_for_tmc_user(Paths.work_dir)

    LockFile.open(Paths.lock_dir + 'main.lock') do
      ignore_signals

      maybe_with_network do
        with_webapp do
          AppLog.info "Startup complete. Host process (#{Process.pid}) waiting for shutdown signal."
          wait_for_signal
        end
      end
    end
  end

private
  def mkdir_p_for_tmc_user(dir)
    FileUtils.mkdir_p(dir)
    ShellUtils.sh! ['chown', tmc_user, dir]
    ShellUtils.sh! ['chgrp', tmc_group, dir]
  end

  def termination_signals
    SignalHandlers.termination_signals
  end

  def ignore_signals
    for signal in termination_signals
      Proc.new do |sig| # So the sig in trap's closure remains unchanged
        Signal.trap(sig) do
          AppLog.info "Caught SIG#{sig}"
        end
      end.call(signal)
    end
  end

  def wait_for_signal
    MiscUtils.wait_for_signal(*termination_signals)
  end

  def with_webapp(&block)
    init_webapp
    begin
      block.call
    ensure
      shutdown_webapp
    end
  end

  def init_webapp
    AppLog.info "Starting webapp"

    File.delete(webapp_pid_file) if File.exist?(webapp_pid_file)

    start_pid = Process.fork do
      $stdin.reopen("/dev/null")
      MiscUtils.cloexec_all_except([$stdin, $stdout, $stderr])
      ProcessUser.drop_root_permanently!
      cmd = [
        'bundle',
        'exec',
        'rackup',
        '--server',
        'webrick',
        '--port',
        @settings['http_port'],
        '--pid',
        webapp_pid_file
      ]

      # We don't use --daemonize since it closes stdout and stderr.
      # Instead we'll daemonize manually.
      exit! if Process.fork
      Process.setsid
      exit! if Process.fork

      Process.exec(Shellwords.join(cmd.map(&:to_s)))
    end
    Process.waitpid(start_pid)

    MiscUtils.poll_until(:time_limit => 15) { File.exist?(webapp_pid_file) }
    @webapp_pid = File.read(webapp_pid_file).strip.to_i
    AppLog.info "Dnsmasq started as #{@webapp_pid}"
  end

  def shutdown_webapp
    AppLog.info "Stopping webapp"
    if @webapp_pid
      # Rack does an orderly shutdown on SIGINT.
      Process.kill("INT", @webapp_pid)
      MiscUtils.wait_until_daemon_stops(webapp_pid_file)
      @webapp_pid = nil
    end
  end

  def maybe_with_network(&block)
    if network_enabled?
      with_tapdevs do |tapdevs|
        maybe_with_dnsmasq(tapdevs) do
          maybe_with_squid(tapdevs) do
            block.call
          end
        end
      end
    end
  end

  def with_tapdevs(&block)
    tapdevs = init_tapdevs
    begin
      block.call(tapdevs)
    ensure
      shutdown_tapdevs(tapdevs)
    end
  end

  def init_tapdevs
    tapdevs = []
    first_ip_range = @settings['network']['private_ip_range_start']
    instance_count.times do |i|
      tapdevs << TapDevice.new("tap_tmc#{i}", "192.168.#{first_ip_range + i}.1", tmc_user)
    end

    if maven_cache_enabled?
      maven_cache = @settings['plugins']['maven_cache']
      tapdevs << TapDevice.new(maven_cache['tap_device'], maven_cache['tap_ip'], tmc_user)
    end

    AppLog.info "Creating tap devices: #{tapdevs.map(&:name).join(', ')}"
    for tapdev in tapdevs
      tapdev.create if !tapdev.exist?
      tapdev.up
    end

    tapdevs
  end

  def shutdown_tapdevs(tapdevs)
    AppLog.info "Destroying tap devices: #{tapdevs.map(&:name).join(', ')}"
    tapdevs.each(&:down)
    tapdevs.each(&:destroy)
  end

  def maybe_with_dnsmasq(tapdevs, &block)
    if dnsmasq_enabled?
      Dnsmasq.with_dnsmasq(tapdevs, &block)
    else
      block.call
    end
  end

  def maybe_with_squid(tapdevs, &block)
    if squid_enabled?
      Squid.with_squid(tapdevs, &block)
    else
      block.call
    end
  end

  def tmc_user
    @settings['tmc_user']
  end

  def tmc_group
    @settings['tmc_group']
  end

  def instance_count
    @settings['max_instances']
  end

  def network_enabled?
    @settings['network']['enabled']
  end

  def squid_enabled?
    @settings['network']['squid']
  end

  def dnsmasq_enabled?
    @settings['network']['squid']
  end

  def maven_cache_enabled?
    @settings['plugins']['maven_cache']['enabled']
  end

  def webapp_pid_file
    Paths.lock_dir + 'rack.pid'
  end
end

daemon_options = {
  :dir_mode => :normal,
  :dir => Paths.lock_dir,
  :log_dir => Paths.log_dir,
  :log_output => true,
  :stop_proc => lambda { Process.kill("INT", Process.pid) }
}
Daemons.run_proc('tmc_sandbox', daemon_options) do
  Dir.chdir(Paths.web_dir)
  WebappProgram.new.run
end

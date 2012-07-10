#!/usr/bin/env ruby
# Entrypoint to the web interface.
# See site.defaults.yml for configuration.

require 'fileutils'
require 'lockfile'
require 'etc'
require 'shellwords'

require "#{File.dirname(File.realpath(__FILE__))}/init.rb"
require 'settings'
require 'tap_device'
require 'misc_utils'

class WebappProgram
  def initialize
    @settings = Settings.get
  end

  def run(args)
    raise "This should be run as root." if Process.uid != 0

    mkdir_p_for_tmc_user(Paths.lock_dir)
    mkdir_p_for_tmc_user(Paths.work_dir)

    Lockfile((Paths.lock_dir + 'main.lock').to_s) do
      run_preliminary_checks
      ignore_signals

      begin
        if network_enabled?
          init_tapdevs
          init_dnsmasq if dnsmasq_enabled?
          init_squid if squid_enabled?
        end
        init_webapp

        puts "Startup complete. Host process (#{Process.pid}) waiting for shutdown signal."
        wait_for_signal
      ensure
        shutdown_webapp
        if network_enabled?
          shutdown_squid if squid_enabled?
          shutdown_dnsmasq if dnsmasq_enabled?
          shutdown_tapdevs
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

  def run_preliminary_checks
    begin
      Etc.getpwnam(tmc_user)
    rescue
      raise "User doesn't exist: #{tmc_user}"
    end

    begin
      Etc.getgrnam(tmc_group)
    rescue
      raise "Group doesn't exist: #{tmc_group}"
    end
  end

  def termination_signals
    ["TERM", "INT", "HUP", "USR1", "USR2"]
  end

  def ignore_signals
    for signal in termination_signals
      Proc.new do |sig| # So the sig in trap's closure remains unchanged
        Signal.trap(sig) do
          puts "Caught SIG#{sig}"
        end
      end.call(signal)
    end
  end

  def wait_for_signal
    MiscUtils.wait_for_signal(*termination_signals)
  end

  def init_webapp
    #TODO: (and see if --pid makes it background. Don't want that.)
    #bundle exec rackup --server webrick --port #{port} --pid webrick.pid >> webrick.log 2>&1
  end

  def shutdown_webapp
    #TODO
  end

  def init_tapdevs
    @tapdevs = []
    first_ip_range = @settings['network']['private_ip_range_start']
    instance_count.times do |i|
      @tapdevs << TapDevice.new("tap_tmc#{i}", "192.168.#{first_ip_range + i}.1", tmc_user)
    end

    puts "Creating tap devices: #{@tapdevs.map(&:name).join(', ')}"
    for tapdev in @tapdevs
      tapdev.create if !tapdev.exist?
      tapdev.up
    end
  end

  def shutdown_tapdevs
    puts "Destroying tap devices: #{@tapdevs.map(&:name).join(', ')}"
    @tapdevs.each(&:down)
    @tapdevs.each(&:destroy)
    @tapdevs = []
  end

  def init_dnsmasq
    puts "Starting dnsmasq"
    pid_file = Paths.work_dir + 'dnsmasq.pid'
    cmd = [
      Paths.dnsmasq_path.to_s,
      "--keep-in-foreground",
      "--conf-file=-", #don't use global conf file
      "--user=#{tmc_user}",
      "--group=#{tmc_group}",
      "--pid-file=#{pid_file}",
      "--bind-interfaces",
      "--domain-needed", # Prevent lookups on local network. Might help avoid leaking info about network.
      "--no-hosts"
    ]

    cmd += @tapdevs.map {|dev| "--interface=#{dev.name}" }
    cmd += @tapdevs.map {|dev| "--no-dhcp-interface=#{dev.name}" }

    @dnsmasq_pid = Process.fork do
      $stdin.reopen("/dev/null")
      Process.exec(*cmd)
    end
    puts "Dnsmasq started as #{@dnsmasq_pid}"
  end

  def shutdown_dnsmasq
    if @dnsmasq_pid
      puts "Shutting down dnsmasq"
      Process.kill("SIGTERM", @dnsmasq_pid)
      Process.waitpid(@dnsmasq_pid)
    end
  end

  def init_squid
    puts "Starting squid"
    write_squid_config_file

    cmd = [Paths.squid_path.to_s, "-d", "error", "-N"]

    @squid_pid = Process.fork do
      $stdin.reopen("/dev/null")
      $stdout.reopen(Paths.squid_log_path, 'a')
      $stderr.reopen($stdout)
      Process.exec(*cmd)
    end
    puts "Squid started as #{@squid_pid}"
  end

  def write_squid_config_file
    config = <<EOS
acl manager proto cache_object
acl localhost src 127.0.0.1/32 ::1
acl to_localhost dst 127.0.0.0/8 0.0.0.0/32 ::1

acl SSL_ports port 443
acl Safe_ports port 80		# http
acl Safe_ports port 8080  # alternative http
acl Safe_ports port 443		# https
acl Safe_ports port 1025-65535	# unregistered ports
acl Safe_ports port 280		# http-mgmt
acl Safe_ports port 488		# gss-http
acl Safe_ports port 591		# filemaker
acl Safe_ports port 777		# multiling http
acl CONNECT method CONNECT
EOS

    for dev in @tapdevs
      config += "acl localnet src #{dev.subnet}\n"
    end

    config += <<EOS
http_access allow manager localhost
http_access deny manager
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

http_access deny to_localhost
http_access allow localnet
http_access allow localhost

http_access deny all

http_port 3128

cache_dir ufs #{Paths.squidroot_dir}/var/cache 100 16 256

coredump_dir #{Paths.squidroot_dir}/var/cache

refresh_pattern -i (/cgi-bin/|\?) 0	0%	0
refresh_pattern .		0	20%	4320

cache_effective_user #{tmc_user}
cache_effective_group #{tmc_group}
EOS
    File.open(Paths.squid_config_path, 'wb') {|f| f.write(config)}
  end

  def shutdown_squid
    if @squid_pid
      puts "Shutting down squid"
      Process.kill("SIGTERM", @squid_pid)
      Process.waitpid(@squid_pid)
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
end


WebappProgram.new.run(ARGV)

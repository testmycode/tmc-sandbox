
require 'paths'
require 'app_log'
require 'settings'
require 'shell_utils'
require 'misc_utils'

module Squid
  def self.with_squid(tapdevs, &block)
    pid = start(tapdevs)
    begin
      block.call
    ensure
      stop(pid)
    end
  end

  def self.start(tapdevs)
    AppLog.info "Starting squid"
    chown_squidroot_var
    ensure_swap_dirs_created
    write_config_file(tapdevs)

    cmd = [Paths.squid_path.to_s, "-d", "error"]

    File.delete(pid_file) if File.exist?(pid_file)

    start_pid = Process.fork do
      $stdin.reopen("/dev/null")
      $stdout.reopen(Paths.squid_startup_log_path, 'a')
      $stderr.reopen($stdout)
      MiscUtils.cloexec_all_except([$stdin, $stdout, $stderr])
      Process.exec(*cmd)
    end
    Process.waitpid(start_pid)

    MiscUtils.poll_until(:time_limit => 15) { File.exist?(pid_file) }
    pid = File.read(pid_file).strip.to_i
    AppLog.info "Squid started as #{pid}"
    pid
  end

  def self.stop(pid)
    AppLog.info "Shutting down squid"
    Process.kill("SIGTERM", pid)
    MiscUtils.wait_until_daemon_stops(pid_file)
  end

  def self.pid_file
    Paths.squidroot_dir + 'var' + 'run' + 'squid.pid'
  end

private
  def self.chown_squidroot_var
    ShellUtils.sh!(['chown', '-R', Settings.tmc_user, "#{Paths.squidroot_dir}/var"])
    ShellUtils.sh!(['chgrp', '-R', Settings.tmc_group, "#{Paths.squidroot_dir}/var"])
  end

  def self.ensure_swap_dirs_created
    if !File.exist?("#{Paths.squidroot_dir}/var/cache/00")
      AppLog.info "Creating squid cache directories"
      ShellUtils.sh!([Paths.squid_path.to_s, '-z'])
    end
  end

  def self.write_config_file(tapdevs)
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

    for dev in tapdevs
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

cache_effective_user #{Settings.tmc_user}
cache_effective_group #{Settings.tmc_group}

shutdown_lifetime 1 seconds
EOS
    File.open(Paths.squid_config_path, 'wb') {|f| f.write(config)}
  end
end

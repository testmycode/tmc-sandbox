
require 'paths'
require 'settings'
require 'app_log'
require 'misc_utils'

module Dnsmasq
  def self.with_dnsmasq(tapdevs, &block)
    pid = start(tapdevs)
    begin
      block.call
    ensure
      stop(pid)
    end
  end

  def self.start(tapdevs)
    AppLog.info "Starting dnsmasq"
    cmd = [
      Paths.dnsmasq_path.to_s,
      "--conf-file=-", #don't use global conf file
      "--user=#{Settings.tmc_user}",
      "--group=#{Settings.tmc_group}",
      "--pid-file=#{pid_file}",
      "--bind-interfaces",
      "--domain-needed", # Prevent lookups on local network. Might help avoid leaking info about network.
      "--no-hosts"
    ]

    cmd += tapdevs.map {|dev| "--interface=#{dev.name}" }
    cmd += tapdevs.map {|dev| "--no-dhcp-interface=#{dev.name}" }

    File.delete(pid_file) if File.exist?(pid_file)

    start_pid = Process.fork do
      $stdin.reopen("/dev/null")
      MiscUtils.cloexec_all_except([$stdin, $stdout, $stderr])
      Process.exec(*cmd)
    end
    Process.waitpid(start_pid)

    MiscUtils.poll_until(:time_limit => 15) { File.exist?(pid_file) }
    pid = File.read(pid_file).strip.to_i
    AppLog.info "Dnsmasq started as #{pid}"
    pid
  end

  def self.stop(pid)
    AppLog.info "Shutting down dnsmasq"
    Process.kill("SIGTERM", pid)
    MiscUtils.wait_until_daemon_stops(pid_file)
  end

  def self.pid_file
    Paths.lock_dir + 'dnsmasq.pid'
  end
end

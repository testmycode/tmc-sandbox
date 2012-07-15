
require 'paths'
require 'settings'
require 'app_log'

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
    pid_file = Paths.work_dir + 'dnsmasq.pid'
    cmd = [
      Paths.dnsmasq_path.to_s,
      "--keep-in-foreground",
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

    pid = Process.fork do
      $stdin.reopen("/dev/null")
      MiscUtils.cloexec_all_except([$stdin, $stdout, $stderr])
      Process.exec(*cmd)
    end
    AppLog.info "Dnsmasq started as #{pid}"
    pid
  end

  def self.stop(pid)
    AppLog.info "Shutting down dnsmasq"
    Process.kill("SIGTERM", pid)
    Process.waitpid(pid)
  end
end

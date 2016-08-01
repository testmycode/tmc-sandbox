
require 'misc_utils_ext'

module MiscUtils
  # Methods defined in C:
  #   self.open_fds()
  #     returns an array of open FDs.
  #
  #   self.cloexec(fd)
  #     Enables O_CLOEXEC on the given FD.
  #     Done in C because Ruby won't let us open IO objects on
  #     its internal FDs.
  #
  #   self.wait_for_signal(signal1, signal2, ...)
  #     Waits for and ignores any of the given signals.
  #     I'm not exactly sure why but a waited signal may still be delivered
  #     for some reason and so ought to be trapped just in case.
  #     Returns the name of the signal caught as a string without the 'SIG' prefix.
  #

  # Sets O_CLOEXEC on all except the given FDs
  def self.cloexec_all_except(fds)
    fds = to_fd_numbers(fds)
    for fd in open_fds - fds
      cloexec(fd)
    end
  end

  def self.cloexec_all
    for fd in open_fds
      cloexec(fd)
    end
  end

  # Returns the current backtrace as an array. A debugging aid.
  def self.current_backtrace
    bt = []
    begin
      raise ''
    rescue
      bt = $!.backtrace
      bt.shift
    end
    bt
  end

  def self.poll_until(options = {}, &block)
    options = {
      :interval => 0.1,
      :time_limit => nil,
      :timeout_error => "timeout"
    }.merge(options)
    start_time = Time.now
    while !block.call
      if options[:time_limit] && Time.now - start_time > options[:time_limit]
        raise options[:timeout_error]
      end
      sleep options[:interval]
    end
  end

  def self.wait_until_daemon_stops(pid_file)
    poll_until do
      begin
        pid = File.read(pid_file).strip.to_i
        !process_exists?(pid)
      rescue
        !File.exist?(pid_file)
      end
    end
  end

  def self.process_exists?(pid)
    begin
      Process.getpgid(pid)
      true
    rescue Errno::ESRCH
      false
    end
  end

private
  def self.to_fd_numbers(fds)
    fds.map {|fd| if fd.respond_to?(:fileno) then fd.fileno else fd end }
  end
end

